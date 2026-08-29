// Texts and emails a driver the moment a dispatcher/super admin approves
// their self-signup (flips `is_active` from false to true - see migration
// 0014_driver_self_signup.sql) - SMS if they have a phone on file, email
// if they have an address. Wired up as a Supabase Database Webhook
// (Database -> Webhooks in the dashboard) on the "profiles" table for
// UPDATE - see the README for the exact setup steps. Runs with the
// service-role key, same reasoning as the other admin-*/notify-*
// functions.
// Deploy with `supabase functions deploy notify-driver-approved`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { jsonResponse } from "../_shared/cors.ts";

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
  try {
    const payload = await req.json();
    // Only fire on the actual pending -> approved transition, not every
    // profile edit (name changes, phone updates, ...) and not the reverse
    // (deactivating someone). Database Webhooks include both the new and
    // previous row for UPDATE events.
    const wasInactive = payload?.old_record?.is_active === false;
    const nowActive = payload?.record?.is_active === true;
    if (!wasInactive || !nowActive) {
      return jsonResponse({ skipped: true });
    }

    // Only trust the profile id from the webhook payload - re-fetch
    // everything else fresh from the database so a forged payload can't be
    // used to email made-up content to an arbitrary address.
    const profileId = payload?.record?.id as string | undefined;
    if (!profileId) return jsonResponse({ error: "No profile id" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: driver, error: driverError } = await admin
      .from("profiles")
      .select("full_name, email, phone, role")
      .eq("id", profileId)
      .single();
    if (driverError || !driver) {
      return jsonResponse({ error: "Profile not found" }, 404);
    }
    if (driver.role !== "driver") {
      return jsonResponse({ skipped: true });
    }

    let sent: boolean | undefined;
    if (driver.email) {
      sent = await sendEmail(
        driver.email,
        "Your SuperD driver account is approved",
        `
          <p>Hi ${driver.full_name},</p>
          <p>Good news - your SuperD driver account has been approved. You
          can now sign in to the app and start receiving deliveries.</p>
        `,
      );
    }
    let sentSms: boolean | undefined;
    if (driver.phone) {
      sentSms = await sendSms(
        driver.phone as string,
        `Hi ${driver.full_name}, good news - your SuperD driver account ` +
          `has been approved. Sign in to the app to start receiving ` +
          `deliveries.`,
      );
    }
    return jsonResponse({ sent, sentSms });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
