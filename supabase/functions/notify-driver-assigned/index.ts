// Texts the customer when a driver is assigned to their delivery, with the
// rider's name and phone number. Wired up as a Supabase Database Webhook
// (Database -> Webhooks in the dashboard) on the "deliveries" table for
// INSERT and UPDATE - see the README for the exact setup steps. Runs with
// the service-role key, same reasoning as the other admin-* functions.
// Deploy with `supabase functions deploy notify-driver-assigned`.
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

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    // Only trust the delivery id from the webhook payload - re-fetch
    // everything else fresh from the database so a forged payload can't be
    // used to fire an SMS with made-up content to an arbitrary number.
    const deliveryId = payload?.record?.id as string | undefined;
    if (!deliveryId) return jsonResponse({ error: "No delivery id" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: delivery, error: deliveryError } = await admin
      .from("deliveries")
      .select("tracking_code, customer_name, customer_phone, assigned_driver_id")
      .eq("id", deliveryId)
      .single();
    if (deliveryError || !delivery) {
      return jsonResponse({ error: "Delivery not found" }, 404);
    }
    if (!delivery.assigned_driver_id || !delivery.customer_phone) {
      // Nothing to notify - no driver assigned yet, or no phone on file.
      return jsonResponse({ skipped: true });
    }

    const { data: driver, error: driverError } = await admin
      .from("profiles")
      .select("full_name, phone")
      .eq("id", delivery.assigned_driver_id)
      .single();
    if (driverError || !driver) {
      return jsonResponse({ error: "Driver not found" }, 404);
    }

    const message =
      `Hi ${delivery.customer_name}, your SuperD delivery ` +
      `(${delivery.tracking_code}) has been assigned to a rider: ` +
      `${driver.full_name}, ${driver.phone ?? "phone not on file"}. ` +
      `They'll be in touch soon.`;

    const sent = await sendSms(delivery.customer_phone, message);
    return jsonResponse({ sent });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
