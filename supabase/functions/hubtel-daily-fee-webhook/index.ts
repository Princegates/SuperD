// Receives Hubtel's callback once a daily-fee Mobile Money charge (started
// by hubtel-daily-fee-charge) resolves, and flips the matching
// driver_daily_fees row to 'paid' or 'failed'. Called by Hubtel's servers
// directly, not by the app - so it can't require a Supabase user JWT (see
// verify_jwt = false for this function in supabase/config.toml). Instead
// it's protected by a shared secret we generate ourselves and put in the
// callback URL (see HUBTEL_WEBHOOK_SECRET below) - Hubtel doesn't
// document a signed-webhook scheme precisely enough here to implement
// against, so this is the practical alternative: anyone hitting this
// endpoint without knowing that secret gets a 401.
//
// IMPORTANT: the exact shape of Hubtel's callback payload (field names,
// nesting) should be verified against your own Hubtel dashboard/sandbox
// test callbacks before going live - this reads the fields Hubtel's
// documented Receive Money API is known to send, but third-party API
// details do shift over time.
//
// Deploy with `supabase functions deploy hubtel-daily-fee-webhook --no-verify-jwt`
// (or set verify_jwt = false for it in supabase/config.toml, already done
// in this repo).
import { createClient } from "jsr:@supabase/supabase-js@2";
import { jsonResponse } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const expectedSecret = Deno.env.get("HUBTEL_WEBHOOK_SECRET");
    if (expectedSecret && url.searchParams.get("secret") !== expectedSecret) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const payload = await req.json().catch(() => null);
    if (!payload) return jsonResponse({ error: "Invalid payload" }, 400);

    // Hubtel's Receive Money callback nests the result under `Data`, with
    // the reference we supplied as `ClientReference` and the outcome as
    // `Status` ("Success" | "Failed" / "Paid" | "Unpaid" depending on the
    // exact product) - accept a couple of likely shapes rather than
    // hard-failing on one.
    const data = payload.Data ?? payload.data ?? payload;
    const clientReference = data?.ClientReference ?? data?.clientReference ??
      payload?.ClientReference;
    const status = String(
      data?.Status ?? data?.status ?? payload?.Status ?? "",
    ).toLowerCase();
    const transactionId = data?.TransactionId ?? data?.transactionId ?? null;

    if (!clientReference) {
      console.error(
        "hubtel-daily-fee-webhook: no ClientReference in payload -",
        payload,
      );
      return jsonResponse({ error: "Missing ClientReference" }, 400);
    }

    const isSuccess = ["success", "paid", "completed"].includes(status);
    const isFailure = ["failed", "unpaid", "cancelled", "canceled"].includes(
      status,
    );
    if (!isSuccess && !isFailure) {
      console.error(
        `hubtel-daily-fee-webhook: unrecognized status "${status}" -`,
        payload,
      );
      // Acknowledge anyway (200) so Hubtel doesn't retry forever on a
      // status value this function just doesn't recognize yet - but skip
      // updating anything, leaving the row 'pending' for manual review.
      return jsonResponse({ ok: true, note: "Unrecognized status, not applied" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: existing } = await admin
      .from("driver_daily_fees")
      .select("id, status")
      .eq("hubtel_client_reference", clientReference)
      .maybeSingle();
    if (!existing) {
      console.error(
        `hubtel-daily-fee-webhook: no row for reference ${clientReference}`,
      );
      return jsonResponse({ error: "Unknown reference" }, 404);
    }
    // Idempotent - a duplicate/retried callback for an already-settled
    // row is a no-op, not an error.
    if (existing.status === "paid" || existing.status === "failed") {
      return jsonResponse({ ok: true });
    }

    const { error: updateError } = await admin
      .from("driver_daily_fees")
      .update({
        status: isSuccess ? "paid" : "failed",
        paid_at: isSuccess ? new Date().toISOString() : null,
        hubtel_transaction_id: transactionId,
      })
      .eq("id", existing.id);
    if (updateError) {
      console.error("hubtel-daily-fee-webhook: update failed -", updateError);
      return jsonResponse({ error: "Could not update payment record" }, 500);
    }

    return jsonResponse({ ok: true });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
