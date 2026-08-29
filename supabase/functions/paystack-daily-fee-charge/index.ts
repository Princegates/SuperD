// Charges a driver's Mobile Money wallet for today's daily platform fee
// via Paystack's Charge API (POST /charge with a mobile_money object) -
// the driver gets an approval prompt on their phone (MTN MoMo PIN prompt,
// or a Vodafone Cash/AirtelTigo Money approval flow), and Paystack calls
// paystack-daily-fee-webhook once it resolves.
//
// IMPORTANT: this is written against Paystack's publicly documented
// Charge API shape (mobile_money charging for Ghana) as of this app's
// development - verify the endpoint and field names against your own
// Paystack dashboard / paystack.com/docs before relying on this in
// production, and test with Paystack's test secret key first. Third-party
// API details do change; this function fails loudly (not silently) if
// Paystack's response doesn't look like what's expected, rather than
// pretending to succeed.
//
// One case this deliberately does NOT handle: if Paystack's response
// comes back needing an OTP submitted (`data.status === "send_otp"`) -
// uncommon for a Ghana mobile money charge, but possible depending on the
// provider/account - there's no in-app screen to enter one, so this tells
// the driver to use the manual reference option instead rather than
// silently stalling. Building an OTP-entry step is a reasonable follow-up
// if this turns out to happen often in practice.
//
// Needs one secret set first (`supabase secrets set ...`):
//   PAYSTACK_SECRET_KEY   - from your Paystack dashboard's API Keys page
// Deploy with `supabase functions deploy paystack-daily-fee-charge`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

// SuperD's own network codes (used by the driver-facing network picker)
// mapped to Paystack's mobile_money provider codes.
const NETWORK_TO_PAYSTACK_PROVIDER: Record<string, string> = {
  "mtn-gh": "mtn",
  "vodafone-gh": "vod",
  "tigo-gh": "atl",
};

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
      .select("role, full_name, phone, email")
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
    const provider = NETWORK_TO_PAYSTACK_PROVIDER[network];
    if (!provider) {
      return jsonResponse(
        { error: "Choose a Mobile Money network (MTN, Vodafone, or AirtelTigo)" },
        400,
      );
    }

    const { data: settings } = await admin
      .from("app_settings")
      .select("currency")
      .limit(1)
      .single();
    const currency = settings?.currency ?? "GHS";

    // Never trust a client-supplied amount - the total owed is always
    // computed server-side: the tier the driver's today's completed count
    // falls into (minus whatever's already paid/waived today), plus
    // anything still due on their per-delivery commission ledger - see
    // driver_total_amount_due() in 0050_bundle_commission_with_daily_fee.sql.
    const { data: amountData, error: amountError } = await admin.rpc(
      "driver_total_amount_due",
      { p_driver_id: driverId },
    );
    if (amountError) {
      console.error(
        "paystack-daily-fee-charge: driver_total_amount_due failed -",
        amountError,
      );
      return jsonResponse(
        { error: "Could not work out what's owed. Please try again." },
        500,
      );
    }
    const amount = Number(amountData ?? 0);
    if (!(amount > 0)) {
      return jsonResponse(
        { error: "Today's fee is already settled" },
        400,
      );
    }

    const secretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!secretKey) {
      return jsonResponse(
        {
          error:
            "Mobile Money collection isn't configured yet - ask your admin to set it up, or pay via the manual reference option instead.",
        },
        500,
      );
    }

    const today = new Date().toISOString().slice(0, 10);
    const { data: existingPending } = await admin
      .from("driver_daily_fees")
      .select("id")
      .eq("driver_id", driverId)
      .eq("fee_date", today)
      .eq("status", "pending")
      .eq("payment_method", "paystack")
      .maybeSingle();

    const reference = `daily-fee-${driverId}-${today}-${
      crypto.randomUUID().slice(0, 8)
    }`;

    // Paystack amounts are always in the currency's smallest unit - GHS
    // pesewas, so multiply by 100. Paystack also requires an email even
    // for a Mobile Money charge (it's part of the charge object, not used
    // to contact the driver) - falls back to a synthetic address built
    // from their id if they never set one, since it's a required field
    // regardless of whether they have a real address on file.
    const paystackRes = await fetch("https://api.paystack.co/charge", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: callerProfile.email ?? `${driverId}@drivers.superd.app`,
        amount: Math.round(amount * 100),
        currency,
        reference,
        mobile_money: { phone, provider },
      }),
    });

    const paystackData = await paystackRes.json().catch(() => null);
    if (!paystackRes.ok || !paystackData) {
      console.error(
        `paystack-daily-fee-charge: Paystack responded ${paystackRes.status} -`,
        paystackData,
      );
      return jsonResponse(
        { error: "Mobile Money request failed. Please try again." },
        502,
      );
    }

    const chargeStatus = paystackData?.data?.status as string | undefined;
    if (chargeStatus === "send_otp") {
      // Paystack wants an OTP this app has no screen to collect - rather
      // than silently stalling the driver, tell them plainly and point
      // at the fallback that always works.
      return jsonResponse(
        {
          error:
            "This Mobile Money number needs a one-time code we can't collect here yet. Please use the manual reference option instead.",
        },
        400,
      );
    }
    if (chargeStatus !== "pay_offline" && chargeStatus !== "success") {
      console.error(
        `paystack-daily-fee-charge: unexpected Paystack status "${chargeStatus}" -`,
        paystackData,
      );
      return jsonResponse(
        { error: "Mobile Money request failed. Please try again." },
        502,
      );
    }

    // Record the attempt regardless of which of the two expected statuses
    // came back - the webhook is the source of truth for the final
    // outcome either way. A driver can have more than one row per day now
    // (a top-up after crossing a tier), so this updates the existing
    // pending paystack row for today if there is one (a retried charge),
    // rather than inserting a duplicate.
    const record = {
      driver_id: driverId,
      fee_date: today,
      amount,
      currency,
      status: "pending",
      payment_method: "paystack",
      payment_reference: reference,
      payment_transaction_id: paystackData?.data?.id?.toString() ?? null,
    };
    const { error: writeError } = existingPending
      ? await admin
        .from("driver_daily_fees")
        .update(record)
        .eq("id", existingPending.id)
      : await admin.from("driver_daily_fees").insert(record);
    if (writeError) {
      console.error("paystack-daily-fee-charge: write failed -", writeError);
      return jsonResponse(
        { error: "Could not record the payment attempt. Please try again." },
        500,
      );
    }

    return jsonResponse({
      status: "pending",
      message: paystackData?.data?.display_text ??
        "Check your phone to approve the Mobile Money payment.",
    });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
