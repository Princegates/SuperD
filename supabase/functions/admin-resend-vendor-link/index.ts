// Re-sends a vendor's own public link (SMS + email) on demand - for when
// the original notify-vendor-registered message never arrived and a
// dispatcher/super admin wants to resend it from the Console rather than
// reading the link out over the phone. Deliberately only resends the
// vendor's own message, not the "new vendor registered" staff broadcast
// notify-vendor-registered also sends at registration - staff already
// heard about this vendor once, resending that isn't the point here.
// Called directly by an authenticated admin client (not a webhook), so
// this keeps the platform default verify_jwt = true and additionally
// checks the caller's own role, same pattern as admin-create-driver/
// admin-delete-driver.
// Deploy with `supabase functions deploy admin-resend-vendor-link`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { sendSms } from "../_shared/sms.ts";

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

    const { data: callerProfile } = await admin
      .from("profiles")
      .select("role")
      .eq("id", userData.user.id)
      .single();
    if (
      !callerProfile ||
      !["dispatcher", "super_admin"].includes(callerProfile.role)
    ) {
      return jsonResponse({ error: "Not authorized" }, 403);
    }

    const body = await req.json();
    const vendorId = body.vendorId as string | undefined;
    if (!vendorId) return jsonResponse({ error: "vendorId is required" }, 400);

    const { data: vendor, error: vendorError } = await admin
      .from("vendors")
      .select("vendor_name, code, orders_code, email, phone")
      .eq("id", vendorId)
      .single();
    if (vendorError || !vendor) {
      return jsonResponse({ error: "Vendor not found" }, 404);
    }

    const appBaseUrl = Deno.env.get("APP_BASE_URL");
    const base = appBaseUrl ? appBaseUrl.replace(/\/+$/, "") : null;
    const link = base ? `${base}/v/${vendor.code}` : null;
    const ordersLink = base ? `${base}/vendor-orders/${vendor.orders_code}` : null;
    if (!link) {
      return jsonResponse({ error: "APP_BASE_URL is not set" }, 500);
    }
    if (!vendor.phone && !vendor.email) {
      return jsonResponse(
        { error: "This vendor has no phone or email on file" },
        400,
      );
    }

    let sentSms: boolean | undefined;
    if (vendor.phone) {
      sentSms = await sendSms(
        vendor.phone as string,
        `Hi ${vendor.vendor_name}, here's your SuperD link again: ${link}. ` +
          `Your private orders link: ${ordersLink}`,
      );
    }
    let sentEmail: boolean | undefined;
    if (vendor.email) {
      sentEmail = await sendEmail(
        vendor.email as string,
        "Your SuperD delivery link",
        `
          <p>Hi ${vendor.vendor_name},</p>
          <p>Here's your customer link again - they'll use it to request a
          delivery from you:</p>
          <p><a href="${link}">${link}</a></p>
          <p>This second link is private - it shows every order ever placed
          through your link above, so it's only for you. Never share it
          with a customer:</p>
          <p><a href="${ordersLink}">${ordersLink}</a></p>
        `,
      );
    }

    return jsonResponse({ sentSms, sentEmail });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
