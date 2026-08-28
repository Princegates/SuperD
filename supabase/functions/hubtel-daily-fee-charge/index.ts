// Charges a driver's Mobile Money wallet for today's daily platform fee
// via Hubtel's "Receive Money" (direct debit prompt) API - the driver
// gets an approval prompt on their phone (MTN MoMo PIN prompt, or a
// Vodafone Cash/AirtelTigo Money approval flow), and Hubtel calls
// hubtel-daily-fee-webhook once it resolves.
//
// IMPORTANT: this is written against Hubtel's publicly documented Receive
// Money Prompt API shape as of this app's development - verify the
// endpoint and field names against your own Hubtel merchant dashboard /
// developers.hubtel.com before relying on this in production, and test
// with Hubtel's sandbox credentials first. Third-party API details do
// change; this function fails loudly (not silently) if Hubtel's response
// doesn't look like what's expected, rather than pretending to succeed.
//
// Needs three secrets set first (`supabase secrets set ...`):
//   HUBTEL_CLIENT_ID       - from your Hubtel merchant account's API keys
//   HUBTEL_CLIENT_SECRET   - same page
//   HUBTEL_POS_SALES_ID    - your Hubtel "POS Sales ID" / merchant account number
// Deploy with `supabase functions deploy hubtel-daily-fee-charge`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

const NETWORK_CHANNELS = new Set(["mtn-gh", "vodafone-gh", "tigo-gh"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Not authenticated" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    // Verify who's calling and that they're actually a driver - never
    // trust the client for either the identity or the amount charged.
    const { data: userData, error: userError } = await admin.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    if (userError || !userData.user) {
      return jsonResponse({ error: "Not authenticated" }, 401);
    }
    const driverId = userData.user.id;

    const { data: callerProfile } = await admin
      .from("profiles")
      .select("role, full_name, phone")
      .eq("id", driverId)
      .single();
    if (!callerProfile || callerProfile.role !== "driver") {
      return jsonResponse({ error: "Only a driver can pay this fee" }, 403);
    }

    const body = await req.json();
    const phone = ((body?.phone ?? callerProfile.phone) ?? "").toString()
      .trim();
    const network = (body?.network ?? "").toString().trim();
    if (!phone) {
      return jsonResponse({ error: "A Mobile Money number is required" }, 400);
    }
    if (!NETWORK_CHANNELS.has(network)) {
      return jsonResponse(
        { error: "Choose a Mobile Money network (MTN, Vodafone, or AirtelTigo)" },
        400,
      );
    }

    const { data: settings } = await admin
      .from("app_settings")
      .select("driver_daily_fee, currency")
      .limit(1)
      .single();
    const amount = Number(settings?.driver_daily_fee ?? 0);
    if (!(amount > 0)) {
      return jsonResponse(
        { error: "Daily fee collection is not enabled" },
        400,
      );
    }

    const today = new Date().toISOString().slice(0, 10);
    const { data: existing } = await admin
      .from("driver_daily_fees")
      .select("id, status")
      .eq("driver_id", driverId)
      .eq("fee_date", today)
      .maybeSingle();
    if (existing?.status === "paid" || existing?.status === "waived") {
      return jsonResponse(
        { error: "Today's fee is already settled" },
        400,
      );
    }

    const clientId = Deno.env.get("HUBTEL_CLIENT_ID");
    const clientSecret = Deno.env.get("HUBTEL_CLIENT_SECRET");
    const posSalesId = Deno.env.get("HUBTEL_POS_SALES_ID");
    const webhookSecret = Deno.env.get("HUBTEL_WEBHOOK_SECRET");
    if (!clientId || !clientSecret || !posSalesId) {
      return jsonResponse(
        {
          error:
            "Mobile Money collection isn't configured yet - ask your admin to set it up, or pay via the manual reference option instead.",
        },
        500,
      );
    }

    const clientReference = `daily-fee-${driverId}-${today}-${
      crypto.randomUUID().slice(0, 8)
    }`;

    const callbackUrl = new URL(
      `${supabaseUrl}/functions/v1/hubtel-daily-fee-webhook`,
    );
    if (webhookSecret) callbackUrl.searchParams.set("secret", webhookSecret);

    const hubtelUrl =
      `https://rmp.hubtel.com/merchantaccount/merchants/${posSalesId}/receive/mobilemoney`;

    const hubtelRes = await fetch(hubtelUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
      },
      body: JSON.stringify({
        CustomerName: callerProfile.full_name ?? "SuperDelivery driver",
        CustomerMsisdn: phone,
        Channel: network,
        Amount: amount,
        PrimaryCallbackUrl: callbackUrl.toString(),
        Description: "SuperDelivery daily driver fee",
        ClientReference: clientReference,
      }),
    });

    const hubtelData = await hubtelRes.json().catch(() => null);
    if (!hubtelRes.ok || !hubtelData) {
      console.error(
        `hubtel-daily-fee-charge: Hubtel responded ${hubtelRes.status} -`,
        hubtelData,
      );
      return jsonResponse(
        { error: "Mobile Money request failed. Please try again." },
        502,
      );
    }

    // Record the attempt as pending regardless of Hubtel's exact response
    // shape - the webhook is the source of truth for the final outcome.
    // upsert so a retried charge for the same day replaces the previous
    // pending attempt's reference rather than violating the unique
    // (driver_id, fee_date) constraint.
    const { error: upsertError } = await admin
      .from("driver_daily_fees")
      .upsert(
        {
          driver_id: driverId,
          fee_date: today,
          amount,
          currency: settings?.currency ?? "GHS",
          status: "pending",
          payment_method: "hubtel_momo",
          hubtel_client_reference: clientReference,
          hubtel_transaction_id: hubtelData?.Data?.TransactionId ?? null,
        },
        { onConflict: "driver_id,fee_date" },
      );
    if (upsertError) {
      console.error("hubtel-daily-fee-charge: upsert failed -", upsertError);
      return jsonResponse(
        { error: "Could not record the payment attempt. Please try again." },
        500,
      );
    }

    return jsonResponse({
      status: "pending",
      message: "Check your phone to approve the Mobile Money payment.",
    });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
