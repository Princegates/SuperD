// Pushes a driver notice (Console > Notices) to whichever driver(s) it's
// actually for, the moment a dispatcher/super admin posts one - a notice
// only shows on a driver's dashboard today (0046_driver_notices.sql), so a
// driver has to have the app open to see it; this pushes it to their
// device the same way notify-delivery-events already pushes a new
// assignment. Wired up as a Supabase Database Webhook (Database ->
// Webhooks in the dashboard) on the "driver_notices" table for INSERT -
// see the README for the exact setup steps (same pg_net fallback as the
// other notify-* functions if your project doesn't have the Webhooks UI).
// Runs with the service-role key, same reasoning as the other admin-*/
// notify-* functions.
// Deploy with `supabase functions deploy notify-driver-notice`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { jsonResponse } from "../_shared/cors.ts";
import { sendPushToProfile } from "../_shared/fcm.ts";

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    // Only trust the notice id from the webhook payload - re-fetch
    // everything else fresh from the database so a forged payload can't be
    // used to push made-up content to every driver.
    const noticeId = payload?.record?.id as string | undefined;
    if (!noticeId) return jsonResponse({ error: "No notice id" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: notice, error: noticeError } = await admin
      .from("driver_notices")
      .select("title, body, target_driver_id, is_active")
      .eq("id", noticeId)
      .single();
    if (noticeError || !notice) {
      return jsonResponse({ error: "Notice not found" }, 404);
    }
    // A notice can be created inactive (rare, but the column allows it) -
    // nothing to push in that case, same as an expired one wouldn't show
    // on a driver's dashboard either.
    if (!notice.is_active) return jsonResponse({ skipped: true });

    let targetIds: string[];
    if (notice.target_driver_id) {
      targetIds = [notice.target_driver_id as string];
    } else {
      // A broadcast - every active driver, same audience the dashboard's
      // own RLS policy already shows it to.
      const { data: drivers, error: driversError } = await admin
        .from("profiles")
        .select("id")
        .eq("role", "driver")
        .eq("is_active", true);
      if (driversError) {
        return jsonResponse({ error: driversError.message }, 500);
      }
      targetIds = (drivers ?? []).map((d) => d.id as string);
    }

    const results = await Promise.all(
      targetIds.map((driverId) =>
        sendPushToProfile(
          admin,
          driverId,
          notice.title as string,
          notice.body as string,
          { type: "driver_notice", notice_id: noticeId },
        )
      ),
    );
    const pushedTo = results.filter((count) => count > 0).length;

    return jsonResponse({ targeted: targetIds.length, pushedTo });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
