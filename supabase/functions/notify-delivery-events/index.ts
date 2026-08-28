// Two notifications around a delivery's lifecycle, both triggered by the
// same Database Webhook (Database -> Webhooks in the dashboard) on the
// "deliveries" table for INSERT and UPDATE - see the README for the exact
// setup steps:
//
//   1. The moment a delivery is created, the CUSTOMER gets their tracking
//      link (`${APP_BASE_URL}/t/<tracking_code>`) by SMS, and by email
//      too if they gave one on the request form - so they have a way
//      back to it even if they close the page they submitted from.
//   2. Whenever a driver is assigned (at creation, if auto-assigned
//      immediately, or later), both the CUSTOMER and the VENDOR get the
//      rider's name and phone number - SMS always, plus email wherever
//      an address is on file. Every message includes the business's
//      support number so either side has someone to call about a
//      problem.
//
// Runs with the service-role key, same reasoning as the other admin-*
// functions. Deploy with `supabase functions deploy notify-delivery-events`.
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
    // Only trust the delivery id (the event type, and old_record, to tell
    // a genuinely new assignment apart from any other update to an
    // already-assigned delivery) from the webhook payload - everything
    // else is re-fetched fresh from the database so a forged payload
    // can't be used to message an arbitrary number/address with made-up
    // content.
    const deliveryId = payload?.record?.id as string | undefined;
    if (!deliveryId) return jsonResponse({ error: "No delivery id" }, 400);

    const isInsert = payload?.type === "INSERT";
    const newDriverId = payload?.record?.assigned_driver_id as
      | string
      | undefined;
    const oldDriverId = payload?.old_record?.assigned_driver_id as
      | string
      | undefined;
    const isNewAssignment = isInsert
      ? Boolean(newDriverId)
      : Boolean(newDriverId) && newDriverId !== oldDriverId;

    if (!isInsert && !isNewAssignment) {
      // An update that didn't touch assigned_driver_id (status, notes,
      // ...) - nothing either notification cares about.
      return jsonResponse({ skipped: true });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: delivery, error: deliveryError } = await admin
      .from("deliveries")
      .select(
        "tracking_code, customer_name, customer_phone, customer_email, assigned_driver_id, vendor_id",
      )
      .eq("id", deliveryId)
      .single();
    if (deliveryError || !delivery) {
      return jsonResponse({ error: "Delivery not found" }, 404);
    }

    const { data: settings } = await admin
      .from("app_settings")
      .select("support_phone")
      .limit(1)
      .single();
    const supportPhone = settings?.support_phone as string | null | undefined;
    const supportLine = supportPhone
      ? ` Problem with this delivery? Call ${supportPhone}.`
      : "";

    const results: Record<string, boolean> = {};

    // 1. Tracking link - once, at creation, regardless of whether a
    // driver ended up assigned in the same instant.
    if (isInsert) {
      const appBaseUrl = Deno.env.get("APP_BASE_URL");
      const trackingLink = appBaseUrl
        ? `${appBaseUrl.replace(/\/+$/, "")}/t/${delivery.tracking_code}`
        : null;

      if (delivery.customer_phone) {
        results.trackingSms = await sendSms(
          delivery.customer_phone,
          trackingLink
            ? `Hi ${delivery.customer_name}, your SuperD delivery ` +
              `(${delivery.tracking_code}) is on its way. Track it here: ` +
              `${trackingLink}`
            : `Hi ${delivery.customer_name}, your SuperD delivery ` +
              `(${delivery.tracking_code}) has been received.`,
        );
      }
      if (delivery.customer_email && trackingLink) {
        results.trackingEmail = await sendEmail(
          delivery.customer_email,
          `Track your delivery - order ${delivery.tracking_code}`,
          `
            <p>Hi ${delivery.customer_name},</p>
            <p>Your delivery (<strong>${delivery.tracking_code}</strong>) has
            been received. Track it any time here:</p>
            <p><a href="${trackingLink}">${trackingLink}</a></p>
          `,
        );
      } else if (delivery.customer_email && !trackingLink) {
        console.error("notify-delivery-events: APP_BASE_URL is not set");
      }
    }

    // 2. Driver assigned - to the customer and the vendor, whenever a
    // driver is newly on the job.
    if (isNewAssignment && delivery.assigned_driver_id) {
      const { data: driver, error: driverError } = await admin
        .from("profiles")
        .select("full_name, phone")
        .eq("id", delivery.assigned_driver_id)
        .single();
      if (driverError || !driver) {
        return jsonResponse({ ...results, error: "Driver not found" }, 404);
      }

      let vendor:
        | { vendor_name: string; phone: string | null; email: string | null }
        | null = null;
      if (delivery.vendor_id) {
        const { data } = await admin
          .from("vendors")
          .select("vendor_name, phone, email")
          .eq("id", delivery.vendor_id)
          .maybeSingle();
        vendor = data ?? null;
      }

      const driverLine =
        `${driver.full_name}, ${driver.phone ?? "phone not on file"}`;

      if (delivery.customer_phone) {
        results.assignedCustomerSms = await sendSms(
          delivery.customer_phone,
          `Hi ${delivery.customer_name}, your SuperD delivery ` +
            `(${delivery.tracking_code}) has been assigned to a rider: ` +
            `${driverLine}. They'll be in touch soon.${supportLine}`,
        );
      }
      if (delivery.customer_email) {
        results.assignedCustomerEmail = await sendEmail(
          delivery.customer_email,
          `A rider is on the way - order ${delivery.tracking_code}`,
          `
            <p>Hi ${delivery.customer_name},</p>
            <p>Your delivery (<strong>${delivery.tracking_code}</strong>) has
            been assigned to a rider:</p>
            <p><strong>${driver.full_name}</strong><br>${
            driver.phone ?? "Phone not on file"
          }</p>
            ${
            supportPhone
              ? `<p>If there's a problem with this delivery, call ${supportPhone}.</p>`
              : ""
          }
          `,
        );
      }
      if (vendor?.phone) {
        results.assignedVendorSms = await sendSms(
          vendor.phone,
          `SuperD: order ${delivery.tracking_code} for ` +
            `${delivery.customer_name} has been assigned to rider ` +
            `${driverLine}.${supportLine}`,
        );
      }
      if (vendor?.email) {
        results.assignedVendorEmail = await sendEmail(
          vendor.email,
          `Rider assigned - order ${delivery.tracking_code}`,
          `
            <p>Hi ${vendor.vendor_name},</p>
            <p>Order <strong>${delivery.tracking_code}</strong> for
            ${delivery.customer_name} has been assigned to a rider:</p>
            <p><strong>${driver.full_name}</strong><br>${
            driver.phone ?? "Phone not on file"
          }</p>
            ${
            supportPhone
              ? `<p>If there's a problem with this delivery, call ${supportPhone}.</p>`
              : ""
          }
          `,
        );
      }
    }

    return jsonResponse(results);
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
