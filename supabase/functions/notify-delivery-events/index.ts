// Three notifications around a delivery's lifecycle, all triggered by the
// same Database Webhook (Database -> Webhooks in the dashboard) on the
// "deliveries" table for INSERT and UPDATE - see the README for the exact
// setup steps:
//
//   1. The moment a delivery is created, the CUSTOMER gets their tracking
//      link (`${APP_BASE_URL}/t/<tracking_code>`) by SMS (first delivery
//      only - see below) and by email - so they have a way back to it
//      even if they close the page they submitted from. The VENDOR gets
//      a new-order notice the same way.
//   2. Whenever a driver is assigned (at creation, if auto-assigned
//      immediately, or later - including a reassignment after case 3
//      below), both the CUSTOMER and the VENDOR get the rider's name and
//      phone number - SMS on their first delivery only, email always
//      wherever an address is on file. Every message includes the
//      business's support number so either side has someone to call
//      about a problem.
//   3. Whenever a driver cancels a delivery already under way
//      (picked_up/in_transit -> assigned/pending with a different
//      driver - see driver_cancel_delivery() in
//      0036_driver_cancel_and_incident_reporting.sql), an ADMIN gets an
//      alert by email/SMS naming the delivery, the driver who cancelled,
//      and the outcome (reassigned to someone else, or unassigned and
//      needs manual dispatch).
//
// SMS is the expensive leg of all this (Twilio bills per message; email
// via Resend is effectively free at this volume) - so it's sent only to a
// CUSTOMER's or VENDOR's first-ever delivery. From their second delivery
// on, they get email only (see isRepeatCustomer/isRepeatVendor below) -
// unless they somehow have no email on file (only possible for a
// customer/vendor predating email being made required on both request
// forms), in which case SMS keeps going out rather than going silent.
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

// deno-lint-ignore no-explicit-any
async function isRepeatCustomer(
  admin: any,
  phone: string,
  excludeDeliveryId: string,
): Promise<boolean> {
  const { count } = await admin
    .from("deliveries")
    .select("id", { count: "exact", head: true })
    .eq("customer_phone", phone)
    .neq("id", excludeDeliveryId);
  return (count ?? 0) > 0;
}

// deno-lint-ignore no-explicit-any
async function isRepeatVendor(
  admin: any,
  vendorId: string,
  excludeDeliveryId: string,
): Promise<boolean> {
  const { count } = await admin
    .from("deliveries")
    .select("id", { count: "exact", head: true })
    .eq("vendor_id", vendorId)
    .neq("id", excludeDeliveryId);
  return (count ?? 0) > 0;
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

    // Shape-based, like isNewAssignment above - the webhook payload has no
    // "who"/"why", just old/new column values, so this infers "a driver
    // cancelled mid-trip" from the transition itself: already
    // picked_up/in_transit, handed to someone else (or back to the
    // unassigned pool) in the same update. driver_cancel_delivery() is the
    // only code path that produces this exact shape.
    const oldStatus = payload?.old_record?.status as string | undefined;
    const newStatus = payload?.record?.status as string | undefined;
    const isDriverCancellation = !isInsert &&
      Boolean(oldDriverId) &&
      ["picked_up", "in_transit"].includes(oldStatus ?? "") &&
      ["assigned", "pending"].includes(newStatus ?? "") &&
      newDriverId !== oldDriverId;

    if (!isInsert && !isNewAssignment && !isDriverCancellation) {
      // An update that didn't touch assigned_driver_id (status, notes,
      // ...) - nothing any of the three notifications care about.
      return jsonResponse({ skipped: true });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: delivery, error: deliveryError } = await admin
      .from("deliveries")
      .select(
        "tracking_code, customer_name, customer_phone, customer_email, dropoff_address, assigned_driver_id, vendor_id",
      )
      .eq("id", deliveryId)
      .single();
    if (deliveryError || !delivery) {
      return jsonResponse({ error: "Delivery not found" }, 404);
    }

    const { data: settings } = await admin
      .from("app_settings")
      .select("support_phone, admin_alert_email, admin_alert_phone")
      .limit(1)
      .single();
    const supportPhone = settings?.support_phone as string | null | undefined;
    const supportLine = supportPhone
      ? ` Problem with this delivery? Call ${supportPhone}.`
      : "";
    const adminAlertEmail = settings?.admin_alert_email as
      | string
      | null
      | undefined;
    const adminAlertPhone = settings?.admin_alert_phone as
      | string
      | null
      | undefined;

    // Fetched once, up front - both the new-order notice (1b) and the
    // driver-assigned notice (2) message the vendor, and neither needs
    // anything from the other's context.
    let vendor:
      | {
        vendor_name: string;
        phone: string | null;
        email: string | null;
        orders_code: string;
      }
      | null = null;
    if (delivery.vendor_id) {
      const { data } = await admin
        .from("vendors")
        .select("vendor_name, phone, email, orders_code")
        .eq("id", delivery.vendor_id)
        .maybeSingle();
      vendor = data ?? null;
    }

    const appBaseUrl = Deno.env.get("APP_BASE_URL");
    const base = appBaseUrl ? appBaseUrl.replace(/\/+$/, "") : null;

    // See the header comment - SMS only goes to a customer's/vendor's
    // first-ever delivery; from the second one on it's email only,
    // falling back to SMS if there's genuinely no email on file. Computed
    // once and reused for both the tracking/new-order notice below and
    // the driver-assigned notice - both concern the same customer/vendor,
    // so their repeat-or-not status doesn't change between the two.
    const repeatCustomer = delivery.customer_phone
      ? await isRepeatCustomer(admin, delivery.customer_phone, deliveryId)
      : false;
    const repeatVendor = vendor && delivery.vendor_id
      ? await isRepeatVendor(admin, delivery.vendor_id, deliveryId)
      : false;
    const smsCustomer = !repeatCustomer || !delivery.customer_email;
    const smsVendor = !repeatVendor || !vendor?.email;

    const results: Record<string, boolean> = {};

    // 1. Tracking link - once, at creation, regardless of whether a
    // driver ended up assigned in the same instant.
    if (isInsert) {
      const trackingLink = base ? `${base}/t/${delivery.tracking_code}` : null;

      if (delivery.customer_phone && smsCustomer) {
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

      // 1b. New order notice - to the vendor themselves, so they hear
      // about it the same instant the customer does rather than only
      // once a driver happens to be assigned. Every vendor has a phone
      // on file (required at registration) - SMS goes out for their
      // first order only (smsVendor), email always goes out wherever an
      // address is on file.
      if (vendor) {
        const vendorOrdersLink = base
          ? `${base}/vendor-orders/${vendor.orders_code}`
          : null;

        if (vendor.phone && smsVendor) {
          results.newOrderVendorSms = await sendSms(
            vendor.phone,
            `SuperD: new order ${delivery.tracking_code} from ` +
              `${delivery.customer_name}, drop-off: ` +
              `${delivery.dropoff_address}.` +
              (vendorOrdersLink ? ` Track it: ${vendorOrdersLink}` : ""),
          );
        }
        if (vendor.email) {
          results.newOrderVendorEmail = await sendEmail(
            vendor.email,
            `New order received - ${delivery.tracking_code}`,
            `
              <p>Hi ${vendor.vendor_name},</p>
              <p>You've received a new order:</p>
              <p>
                <strong>Order:</strong> ${delivery.tracking_code}<br>
                <strong>Customer:</strong> ${delivery.customer_name}<br>
                <strong>Drop-off:</strong> ${delivery.dropoff_address}
              </p>
              ${
              vendorOrdersLink
                ? `<p>Track it any time here: <a href="${vendorOrdersLink}">${vendorOrdersLink}</a></p>`
                : ""
            }
            `,
          );
        }
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

      const driverLine =
        `${driver.full_name}, ${driver.phone ?? "phone not on file"}`;

      if (delivery.customer_phone && smsCustomer) {
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
      if (vendor?.phone && smsVendor) {
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

    // 3. Driver cancelled mid-trip - alert an admin, whichever way it went.
    if (isDriverCancellation && oldDriverId) {
      const { data: oldDriver } = await admin
        .from("profiles")
        .select("full_name")
        .eq("id", oldDriverId)
        .maybeSingle();
      const oldDriverName = oldDriver?.full_name ?? "A driver";

      let outcomeLine: string;
      if (newDriverId) {
        const { data: newDriver } = await admin
          .from("profiles")
          .select("full_name")
          .eq("id", newDriverId)
          .maybeSingle();
        outcomeLine = `reassigned to ${newDriver?.full_name ?? "another driver"}`;
      } else {
        outcomeLine = "unassigned - needs manual reassignment";
      }

      if (adminAlertPhone) {
        results.cancellationSms = await sendSms(
          adminAlertPhone,
          `SuperD: order ${delivery.tracking_code} was cancelled mid-trip ` +
            `by ${oldDriverName} - ${outcomeLine}.`,
        );
      }
      if (adminAlertEmail) {
        results.cancellationEmail = await sendEmail(
          adminAlertEmail,
          `Driver cancelled mid-trip - order ${delivery.tracking_code}`,
          `
            <p>${oldDriverName} cancelled order
            <strong>${delivery.tracking_code}</strong>
            (${delivery.customer_name}) after already picking it up.</p>
            <p>Outcome: ${outcomeLine}.</p>
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
