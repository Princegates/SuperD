// Texts and emails every active dispatcher/super admin, and the applicant
// themselves, the moment a driver signs themselves up (self-signup lands
// as `is_active = false`, pending approval - see migration
// 0014_driver_self_signup.sql) - SMS wherever a phone is on file, email
// wherever an address is. Wired up as a Supabase Database Webhook
// (Database -> Webhooks in the dashboard) on the "profiles" table for
// INSERT - see the README for the exact setup steps. Runs with the
// service-role key, same reasoning as the other admin-*/notify-*
// functions.
// Deploy with `supabase functions deploy notify-driver-application`.
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
  to: string[],
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
    // Only trust the profile id from the webhook payload - re-fetch
    // everything else fresh from the database so a forged payload can't be
    // used to email made-up content out to the whole team.
    const profileId = payload?.record?.id as string | undefined;
    if (!profileId) return jsonResponse({ error: "No profile id" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: applicant, error: applicantError } = await admin
      .from("profiles")
      .select("full_name, email, phone, role, is_active")
      .eq("id", profileId)
      .single();
    if (applicantError || !applicant) {
      return jsonResponse({ error: "Profile not found" }, 404);
    }
    // Only a pending driver self-signup should trigger this - an
    // admin-created driver/dispatcher lands with is_active already true
    // (see admin-create-driver's app_metadata.created_by_admin), so this
    // webhook naturally skips those.
    if (applicant.role !== "driver" || applicant.is_active) {
      return jsonResponse({ skipped: true });
    }

    const { data: staff, error: staffError } = await admin
      .from("profiles")
      .select("email, phone")
      .in("role", ["dispatcher", "super_admin"])
      .eq("is_active", true);
    if (staffError) {
      return jsonResponse({ error: staffError.message }, 500);
    }
    const staffEmails = (staff ?? [])
      .map((s) => s.email as string)
      .filter((email) => email.length > 0);
    const staffPhones = (staff ?? [])
      .map((s) => s.phone as string | null)
      .filter((phone): phone is string => Boolean(phone));

    let sentToStaff: boolean | undefined;
    if (staffEmails.length > 0) {
      sentToStaff = await sendEmail(
        staffEmails,
        "New driver application on SuperD",
        `
          <p>A new driver has applied to join SuperD:</p>
          <p>
            <strong>Name:</strong> ${applicant.full_name}<br>
            <strong>Email:</strong> ${applicant.email}<br>
            <strong>Phone:</strong> ${applicant.phone ?? "not provided"}
          </p>
          <p>Review and approve them from the Team screen before they can be
          assigned any deliveries.</p>
        `,
      );
    }
    let sentToStaffSms: boolean | undefined;
    if (staffPhones.length > 0) {
      const staffSmsBody = `SuperD: new driver application from ` +
        `${applicant.full_name} (${applicant.phone ?? "no phone on file"}). ` +
        `Review it in the Team screen.`;
      const staffSmsResults = await Promise.all(
        staffPhones.map((phone) => sendSms(phone, staffSmsBody)),
      );
      sentToStaffSms = staffSmsResults.some(Boolean);
    }

    let sentToApplicant: boolean | undefined;
    if (applicant.email) {
      sentToApplicant = await sendEmail(
        [applicant.email as string],
        "We've received your SuperD driver application",
        `
          <p>Hi ${applicant.full_name},</p>
          <p>Thanks for applying to drive with SuperD. A dispatcher or admin
          will review your application shortly - we'll email you again once
          you're approved and ready to start receiving deliveries.</p>
        `,
      );
    }
    let sentToApplicantSms: boolean | undefined;
    if (applicant.phone) {
      sentToApplicantSms = await sendSms(
        applicant.phone as string,
        `Hi ${applicant.full_name}, thanks for applying to drive with ` +
          `SuperD. We'll text/email you once your application is reviewed.`,
      );
    }

    return jsonResponse({
      sentToStaff,
      sentToStaffSms,
      sentToApplicant,
      sentToApplicantSms,
    });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
