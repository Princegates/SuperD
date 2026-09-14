// Completes a driver daily-fee Mobile Money charge that Paystack put into
// the send_otp state (see paystack-daily-fee-charge) - the driver enters
// the one-time code they received, and this submits it to Paystack's
// POST /charge/submit_otp. The final outcome (paid/failed) still arrives
// through paystack-daily-fee-webhook, same as the pay_offline path - this
// function only forwards the code and reports whether Paystack accepted
// it, it never marks the driver_daily_fees row paid itself.
//
// IMPORTANT: written against Paystack's publicly documented submit_otp
// endpoint - verify field names/response shape against your own
// dashboard/docs before relying on this in production, same caveat as
// paystack-daily-fee-charge.
//
// Needs the same PAYSTACK_SECRET_KEY secret as paystack-daily-fee-charge.
// Deploy with `supabase functions deploy paystack-daily-fee-submit-otp`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

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

    const { data: userData, error: userError } = await admin.auth.getUser(
      authHeader.replace("Bearer ", ""),
    );
    if (userError || !userData.user) {
      return jsonResponse({ error: "Not authenticated" }, 401);
    }
    const driverId = userData.user.id;

    const body = await req.json();
    const reference = (body?.reference ?? "").toString().trim();
    const otp = (body?.otp ?? "").toString().trim();
    if (!reference || !otp) {
      return jsonResponse(
        { error: "A code and payment reference are required." },
        400,
      );
    }

    // Only ever act on a row this driver actually owns, still pending,
    // and actually waiting on an OTP - never trust the client-supplied
    // reference alone. This also catches a stale/already-resolved
    // reference (e.g. the webhook already settled it) and reports that
    // plainly instead of re-submitting a code Paystack no longer expects.
    const { data: existing } = await admin
      .from("driver_daily_fees")
      .select("id, status")
      .eq("driver_id", driverId)
      .eq("payment_reference", reference)
      .eq("payment_method", "paystack")
      .maybeSingle();
    if (!existing) {
      return jsonResponse(
        { error: "This payment attempt could not be found. Please try again." },
        404,
      );
    }
    if (existing.status !== "pending") {
      return jsonResponse(
        {
          error: existing.status === "paid"
            ? "This payment has already gone through."
            : "This payment attempt is no longer active. Please try again.",
        },
        409,
      );
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
        `paystack-daily-fee-submit-otp: Paystack responded ${paystackRes.status} -`,
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
      // expired) - let the driver try again with the same reference.
      return jsonResponse({
        status: "send_otp",
        reference,
        message: paystackData?.data?.display_text ??
          "That code didn't work - enter the new one sent to your phone.",
      });
    }
    if (chargeStatus !== "pay_offline" && chargeStatus !== "success") {
      console.error(
        `paystack-daily-fee-submit-otp: unexpected Paystack status "${chargeStatus}" -`,
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
