// Re-sends a delivery's tracking link (SMS + email) to its customer, on
// demand - for when the original notify-delivery-events message never
// arrived (bad number typo since fixed, email bounced, message lost) and
// a dispatcher/super admin wants to resend it from the Console rather
// than reading the tracking code out over the phone. Called directly by
// an authenticated admin client (not a webhook), so this keeps the
// platform default verify_jwt = true and additionally checks the
// caller's own role, same pattern as admin-create-driver/
// admin-delete-driver.
// Deploy with `supabase functions deploy admin-resend-tracking-link`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

async function sendSms(to: string, body: string): Promise<boolean> {
  const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  const fromNumber = Deno.env.get("TWILIO_FROM_NUMBER");
  if (!accountSid || !authToken || !fromNumber) {
    console.error("sendSms: Twilio secrets are not fully set");
    return false;
  }

  try {
    const res = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`,
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`${accountSid}:${authToken}`)}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({ To: to, From: fromNumber, Body: body }),
      },
    );
    if (!res.ok) {
      console.error(
        `sendSms: Twilio responded ${res.status} - ${await res.text()}`,
      );
    }
    return res.ok;
  } catch (e) {
    console.error("sendSms: fetch to Twilio failed -", e);
    return false;
  }
}

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
    const deliveryId = body.deliveryId as string | undefined;
    if (!deliveryId) {
      return jsonResponse({ error: "deliveryId is required" }, 400);
    }

    const { data: delivery, error: deliveryError } = await admin
      .from("deliveries")
      .select("tracking_code, customer_name, customer_phone, customer_email")
      .eq("id", deliveryId)
      .single();
    if (deliveryError || !delivery) {
      return jsonResponse({ error: "Delivery not found" }, 404);
    }

    const appBaseUrl = Deno.env.get("APP_BASE_URL");
    const base = appBaseUrl ? appBaseUrl.replace(/\/+$/, "") : null;
    const trackingLink = base ? `${base}/t/${delivery.tracking_code}` : null;
    if (!trackingLink) {
      return jsonResponse({ error: "APP_BASE_URL is not set" }, 500);
    }
    if (!delivery.customer_phone && !delivery.customer_email) {
      return jsonResponse(
        { error: "This delivery has no phone or email on file" },
        400,
      );
    }

    let sentSms: boolean | undefined;
    if (delivery.customer_phone) {
      sentSms = await sendSms(
        delivery.customer_phone as string,
        `Hi ${delivery.customer_name}, here's your SuperD tracking link ` +
          `for order ${delivery.tracking_code}: ${trackingLink}`,
      );
    }
    let sentEmail: boolean | undefined;
    if (delivery.customer_email) {
      sentEmail = await sendEmail(
        delivery.customer_email as string,
        `Track your delivery - order ${delivery.tracking_code}`,
        `
          <p>Hi ${delivery.customer_name},</p>
          <p>Here's your tracking link for order
          <strong>${delivery.tracking_code}</strong> again:</p>
          <p><a href="${trackingLink}">${trackingLink}</a></p>
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
