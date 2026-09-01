// Charges a vendor's Mobile Money wallet for their one-time subscription
// fee via Paystack's Charge API - same approach as
// paystack-daily-fee-charge, but for a vendor rather than a driver. A
// vendor has no login at all (just their public code), so this is a
// PUBLIC function identified by [code] instead of a Supabase session -
// the amount actually charged always comes from
// charge_vendor_subscription_precheck() server-side, never trusted from
// the client, and that same function rejects the call outright if the
// vendor isn't genuinely in a pending-payment state (already active, no
// fee ever applied, or the feature's since been turned off).
//
// IMPORTANT: same caveat as paystack-daily-fee-charge - written against
// Paystack's publicly documented Charge API shape (mobile_money charging
// for Ghana) as of this app's development; verify against your own
// Paystack dashboard/docs and test with a test secret key first.
//
// Needs the same PAYSTACK_SECRET_KEY secret as the daily-fee functions.
// Deploy with `supabase functions deploy paystack-vendor-subscription-charge`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

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
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const body = await req.json();
    const code = (body?.code ?? "").toString().trim();
    const phone = (body?.phone ?? "").toString().trim();
    const network = (body?.network ?? "").toString().trim();
    if (!code) return jsonResponse({ error: "code is required" }, 400);
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

    const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]
      ?.trim() ?? null;

    const { data: precheck, error: precheckError } = await admin.rpc(
      "charge_vendor_subscription_precheck",
      { p_code: code, p_client_ip: clientIp },
    );
    if (precheckError) {
      return jsonResponse({ error: precheckError.message }, 400);
    }
    const row = Array.isArray(precheck) ? precheck[0] : precheck;
    if (!row) {
      return jsonResponse({ error: "Vendor not found" }, 404);
    }
    const vendorId = row.vendor_id as string;
    const email = row.email as string;
    const amount = Number(row.amount);
    const currency = row.currency as string;

    const secretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!secretKey) {
      return jsonResponse(
        {
          error:
            "Mobile Money collection isn't configured yet - ask your admin to set it up.",
        },
        500,
      );
    }

    const reference = `vendor-sub-${vendorId}-${
      crypto.randomUUID().slice(0, 8)
    }`;

    const paystackRes = await fetch("https://api.paystack.co/charge", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secretKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        amount: Math.round(amount * 100),
        currency,
        reference,
        mobile_money: { phone, provider },
      }),
    });

    const paystackData = await paystackRes.json().catch(() => null);
    if (!paystackRes.ok || !paystackData) {
      console.error(
        `paystack-vendor-subscription-charge: Paystack responded ${paystackRes.status} -`,
        paystackData,
      );
      return jsonResponse(
        { error: "Mobile Money request failed. Please try again." },
        502,
      );
    }

    const chargeStatus = paystackData?.data?.status as string | undefined;
    if (chargeStatus === "send_otp") {
      return jsonResponse(
        {
          error:
            "This Mobile Money number needs a one-time code we can't collect here yet. Try a different number, or ask your admin to activate you manually.",
        },
        400,
      );
    }
    if (chargeStatus !== "pay_offline" && chargeStatus !== "success") {
      console.error(
        `paystack-vendor-subscription-charge: unexpected Paystack status "${chargeStatus}" -`,
        paystackData,
      );
      return jsonResponse(
        { error: "Mobile Money request failed. Please try again." },
        502,
      );
    }

    // The webhook (paystack-daily-fee-webhook, shared with the driver
    // daily fee - see its own comment) is the source of truth for the
    // final outcome - this just records which reference to watch for, so
    // a retry overwrites the previous attempt's reference rather than
    // leaving a stale one behind.
    const { error: writeError } = await admin
      .from("vendors")
      .update({ subscription_payment_reference: reference })
      .eq("id", vendorId);
    if (writeError) {
      console.error(
        "paystack-vendor-subscription-charge: write failed -",
        writeError,
      );
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
