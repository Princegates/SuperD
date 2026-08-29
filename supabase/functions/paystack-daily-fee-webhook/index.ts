// Receives Paystack's webhook once a daily-fee Mobile Money charge
// (started by paystack-daily-fee-charge) resolves, and flips the matching
// driver_daily_fees row to 'paid' or 'failed'. Called by Paystack's
// servers directly, not by the app - so it can't require a Supabase user
// JWT (see verify_jwt = false for this function in supabase/config.toml).
// Instead it verifies Paystack's own signature header (see
// verifySignature() below) - the documented, standard way to confirm a
// webhook request genuinely came from Paystack and wasn't forged.
//
// IMPORTANT: the exact shape of Paystack's webhook payload (event names,
// nesting) should be verified against your own Paystack dashboard/test
// webhooks before going live - this reads the fields Paystack's
// documented Charge events are known to send, but third-party API
// details do shift over time.
//
// Needs the same PAYSTACK_SECRET_KEY secret as paystack-daily-fee-charge
// (used here to verify the signature, not to call the API).
// Deploy with `supabase functions deploy paystack-daily-fee-webhook`
// (or set verify_jwt = false for it in supabase/config.toml, already done
// in this repo).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { jsonResponse } from "../_shared/cors.ts";

// Paystack signs the raw request body with HMAC-SHA512 using your secret
// key, sent as the `x-paystack-signature` header - constant-ish time
// comparison isn't critical here (this isn't a login check), but hex
// string equality is what Paystack's own docs compare.
async function verifySignature(
  rawBody: string,
  signature: string | null,
  secretKey: string,
): Promise<boolean> {
  if (!signature) return false;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secretKey),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(rawBody),
  );
  const computed = Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return computed === signature;
}

Deno.serve(async (req) => {
  try {
    const secretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
    if (!secretKey) {
      console.error("paystack-daily-fee-webhook: PAYSTACK_SECRET_KEY not set");
      return jsonResponse({ error: "Not configured" }, 500);
    }

    const rawBody = await req.text();
    const signature = req.headers.get("x-paystack-signature");
    if (!(await verifySignature(rawBody, signature, secretKey))) {
      return jsonResponse({ error: "Invalid signature" }, 401);
    }

    const payload = JSON.parse(rawBody);
    const event = payload?.event as string | undefined;
    const data = payload?.data ?? {};
    const reference = data?.reference as string | undefined;
    const status = String(data?.status ?? "").toLowerCase();
    const transactionId = data?.id?.toString() ?? null;

    if (!reference) {
      console.error(
        "paystack-daily-fee-webhook: no reference in payload -",
        payload,
      );
      return jsonResponse({ error: "Missing reference" }, 400);
    }

    // Paystack sends events for every kind of transaction on the account,
    // not just this one flow - only charge.success/charge.failed (and the
    // data.status they carry) are relevant here; anything else is
    // acknowledged and ignored.
    const isSuccess = event === "charge.success" || status === "success";
    const isFailure = event === "charge.failed" ||
      ["failed", "abandoned", "reversed"].includes(status);
    if (!isSuccess && !isFailure) {
      return jsonResponse({ ok: true, note: "Event not applicable" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: existing } = await admin
      .from("driver_daily_fees")
      .select("id, status, driver_id")
      .eq("payment_reference", reference)
      .maybeSingle();
    if (!existing) {
      console.error(
        `paystack-daily-fee-webhook: no row for reference ${reference}`,
      );
      return jsonResponse({ error: "Unknown reference" }, 404);
    }
    // Idempotent - a duplicate/retried webhook for an already-settled row
    // is a no-op, not an error.
    if (existing.status === "paid" || existing.status === "failed") {
      return jsonResponse({ ok: true });
    }

    const { error: updateError } = await admin
      .from("driver_daily_fees")
      .update({
        status: isSuccess ? "paid" : "failed",
        paid_at: isSuccess ? new Date().toISOString() : null,
        payment_transaction_id: transactionId,
      })
      .eq("id", existing.id);
    if (updateError) {
      console.error("paystack-daily-fee-webhook: update failed -", updateError);
      return jsonResponse({ error: "Could not update payment record" }, 500);
    }

    // The charge amount already included whatever per-delivery commission
    // was due at the time (see driver_total_amount_due() in
    // 0050_bundle_commission_with_daily_fee.sql) - now that Paystack has
    // confirmed the money actually landed, settle those rows too.
    if (isSuccess) {
      const { error: commissionError } = await admin
        .from("commission_payments")
        .update({ status: "paid", paid_at: new Date().toISOString() })
        .eq("driver_id", existing.driver_id)
        .eq("status", "due");
      if (commissionError) {
        console.error(
          "paystack-daily-fee-webhook: commission settle failed -",
          commissionError,
        );
      }
    }

    return jsonResponse({ ok: true });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
