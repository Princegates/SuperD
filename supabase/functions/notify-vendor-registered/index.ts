// Emails a vendor their unique link the moment they register. Wired up as
// a Supabase Database Webhook (Database -> Webhooks in the dashboard) on
// the "vendors" table for INSERT only - see the README for the exact
// setup steps. Runs with the service-role key, same reasoning as the
// other admin-*/notify-* functions.
// Deploy with `supabase functions deploy notify-vendor-registered`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { jsonResponse } from "../_shared/cors.ts";

async function sendEmail(
  to: string,
  subject: string,
  html: string,
): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.error("sendEmail: RESEND_API_KEY is not set");
    return false;
  }
  const fromEmail =
    Deno.env.get("RESEND_FROM_EMAIL") ?? "SuperD <noreply@superd.anknovate.com>";

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ from: fromEmail, to, subject, html }),
    });
    if (!res.ok) {
      console.error(
        `sendEmail: Resend responded ${res.status} - ${await res.text()}`,
      );
    }
    return res.ok;
  } catch (e) {
    console.error("sendEmail: fetch to Resend failed -", e);
    return false;
  }
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    // Only trust the vendor id from the webhook payload - re-fetch
    // everything else fresh from the database so a forged payload can't
    // be used to email arbitrary made-up content to an arbitrary address.
    const vendorId = payload?.record?.id as string | undefined;
    if (!vendorId) return jsonResponse({ error: "No vendor id" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: vendor, error: vendorError } = await admin
      .from("vendors")
      .select("vendor_name, code, email")
      .eq("id", vendorId)
      .single();
    if (vendorError || !vendor) {
      return jsonResponse({ error: "Vendor not found" }, 404);
    }
    if (!vendor.email) {
      // Nothing to notify - no email on file for this vendor.
      return jsonResponse({ skipped: true });
    }

    const appBaseUrl = Deno.env.get("APP_BASE_URL");
    if (!appBaseUrl) {
      console.error("notify-vendor-registered: APP_BASE_URL is not set");
      return jsonResponse({ error: "APP_BASE_URL is not set" }, 500);
    }
    const link = `${appBaseUrl.replace(/\/+$/, "")}/v/${vendor.code}`;

    const html = `
      <p>Hi ${vendor.vendor_name},</p>
      <p>You're registered on SuperD. Share this link with your customers -
      they'll use it to request a delivery from you, and it also shows you
      your own orders:</p>
      <p><a href="${link}">${link}</a></p>
    `;

    const sent = await sendEmail(vendor.email, "Your SuperD delivery link", html);
    return jsonResponse({ sent });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
