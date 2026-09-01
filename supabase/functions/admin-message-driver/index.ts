// Lets a dispatcher/super admin send one driver a free-form message via
// SMS or email (the caller picks one, not both) - for anything that
// doesn't fit an existing notification (a delivery update, a driver
// notice) and needs a quick, direct word to a specific driver instead of
// a phone call. See the "Message" action on Console/Admin > Drivers.
// Called directly by an authenticated admin client (not a webhook), so
// this keeps the platform default verify_jwt = true and additionally
// checks the caller's own role, same pattern as admin-resend-vendor-link/
// admin-reset-password.
// Deploy with `supabase functions deploy admin-message-driver`.
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

// A blank line becomes a paragraph break - the admin types plain text,
// this is the only formatting a driver's message gets.
function messageToHtml(message: string): string {
  return message
    .split(/\n{2,}/)
    .map((para) => `<p>${para.replace(/\n/g, "<br>")}</p>`)
    .join("\n");
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
    const driverId = body.driverId as string | undefined;
    if (!driverId) return jsonResponse({ error: "driverId is required" }, 400);
    const channel = body.channel as string | undefined;
    if (channel !== "sms" && channel !== "email") {
      return jsonResponse(
        { error: 'channel must be "sms" or "email"' },
        400,
      );
    }
    const message = (body.message as string | undefined)?.trim();
    if (!message) {
      return jsonResponse({ error: "message is required" }, 400);
    }

    const { data: driver, error: driverError } = await admin
      .from("profiles")
      .select("full_name, role, email, phone")
      .eq("id", driverId)
      .single();
    if (driverError || !driver || driver.role !== "driver") {
      return jsonResponse({ error: "Driver not found" }, 404);
    }

    if (channel === "sms") {
      if (!driver.phone) {
        return jsonResponse(
          { error: "This driver has no phone number on file" },
          400,
        );
      }
      const sentSms = await sendSms(driver.phone as string, message);
      return jsonResponse({ sentSms });
    }

    if (!driver.email) {
      return jsonResponse(
        { error: "This driver has no email on file" },
        400,
      );
    }
    const sentEmail = await sendEmail(
      driver.email as string,
      "Message from SuperD",
      `
        <p>Hi ${driver.full_name},</p>
        ${messageToHtml(message)}
      `,
    );
    return jsonResponse({ sentEmail });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
