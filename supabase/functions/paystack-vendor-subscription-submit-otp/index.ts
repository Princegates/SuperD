// Completes a vendor subscription Mobile Money charge that Paystack put
// into the send_otp state (see paystack-vendor-subscription-charge) - the
// vendor enters the one-time code they received, and this submits it to
// Paystack's POST /charge/submit_otp. The final outcome (activating the
// vendor) still arrives through paystack-daily-fee-webhook, same as the
// pay_offline path - this function only forwards the code and reports
// whether Paystack accepted it.
//
// PUBLIC, like paystack-vendor-subscription-charge - a vendor has no
// login, only their own [code]. submit_vendor_subscription_otp_precheck()
// (0090_vendor_subscription_otp_precheck.sql) checks the code+reference
// actually match a live pending attempt and rate-limits the attempt
// before this ever calls Paystack, so a public no-auth endpoint can't be
// used to brute-force a one-time code.
//
// IMPORTANT: written against Paystack's publicly documented submit_otp
// endpoint - verify field names/response shape against your own
// dashboard/docs before relying on this in production, same caveat as
// paystack-vendor-subscription-charge.
//
// Needs the same PAYSTACK_SECRET_KEY secret as the other Paystack
// functions. Deploy with
// `supabase functions deploy paystack-vendor-subscription-submit-otp`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

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
    const reference = (body?.reference ?? "").toString().trim();
    const otp = (body?.otp ?? "").toString().trim();
    if (!code || !reference || !otp) {
      return jsonResponse(
        { error: "A code, reference, and vendor code are required." },
        400,
      );
    }

    const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]
      ?.trim() ?? null;

    const { error: precheckError } = await admin.rpc(
      "submit_vendor_subscription_otp_precheck",
      { p_code: code, p_reference: reference, p_client_ip: clientIp },
    );
    if (precheckError) {
      return jsonResponse({ error: precheckError.message }, 400);
    }

    const secretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!secretKey) {
      return jsonResponse(
        { error: "Mobile Money collection isn't configured yet." },
        500,
      );
    }

    const paystackRes = await fetch(
      "https://api.paystack.co/charge/submit_otp",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${secretKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ otp, reference }),
      },
    );

    const paystackData = await paystackRes.json().catch(() => null);
    if (!paystackRes.ok || !paystackData) {
      console.error(
        `paystack-vendor-subscription-submit-otp: Paystack responded ${paystackRes.status} -`,
        paystackData,
      );
      return jsonResponse(
        { error: "That code didn't work. Please check it and try again." },
        502,
      );
    }

    const chargeStatus = paystackData?.data?.status as string | undefined;
    if (chargeStatus === "send_otp") {
      // Paystack rejected the code and is asking for another one (e.g. it
      // expired) - let the vendor try again with the same reference.
      return jsonResponse({
        status: "send_otp",
        reference,
        message: paystackData?.data?.display_text ??
          "That code didn't work - enter the new one sent to your phone.",
      });
    }
    if (chargeStatus !== "pay_offline" && chargeStatus !== "success") {
      console.error(
        `paystack-vendor-subscription-submit-otp: unexpected Paystack status "${chargeStatus}" -`,
        paystackData,
      );
      return jsonResponse(
        { error: "That code didn't work. Please check it and try again." },
        502,
      );
    }

    return jsonResponse({
      status: "pending",
      message: paystackData?.data?.display_text ??
        "Code accepted - confirming your payment.",
    });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
