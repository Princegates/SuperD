// Creates a driver's or dispatcher's login + profile. Runs with the
// service-role key, which must never be shipped inside the app - this is
// the one place that key is allowed to live. Deploy with
// `supabase functions deploy admin-create-driver`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

function randomPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return btoa(String.fromCharCode(...bytes))
    .replace(/[^a-zA-Z0-9]/g, "")
    .slice(0, 12);
}

// Emails the driver their sign-in details via Resend's HTTP API (the same
// account already used for Supabase Auth's SMTP - see README). Returns
// false (never throws) if it's not configured or the send fails, so
// account creation still succeeds and the dispatcher can share the
// password another way.
async function sendWelcomeEmail(
  email: string,
  fullName: string,
  tempPassword: string,
  roleLabel: string,
): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.error("sendWelcomeEmail: RESEND_API_KEY is not set");
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
      body: JSON.stringify({
        from: fromEmail,
        to: email,
        subject: "Your SuperD account",
        html: `
          <p>Hi ${fullName},</p>
          <p>A SuperD account was created for you as a ${roleLabel}.</p>
          <p>
            <strong>Email:</strong> ${email}<br>
            <strong>Temporary password:</strong> ${tempPassword}
          </p>
          <p>Sign in with these details in the SuperD app. You'll be asked
          to set your own password before you can do anything else.</p>
        `,
      }),
    });
    if (!res.ok) {
      console.error(
        `sendWelcomeEmail: Resend responded ${res.status} - ${await res.text()}`,
      );
    }
    return res.ok;
  } catch (e) {
    console.error("sendWelcomeEmail: fetch to Resend failed -", e);
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

    // Verify who's calling and that they're a dispatcher or super admin -
    // never trust the client, this check happens again here server-side.
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
    const email = (body.email ?? "").trim();
    const fullName = (body.fullName ?? "").trim();
    const phone = (body.phone ?? "").trim() || null;
    const ghanaCardNumber = (body.ghanaCardNumber ?? "").trim() || null;
    const vehicleNumber = (body.vehicleNumber ?? "").trim() || null;
    const role = body.role === "dispatcher" ? "dispatcher" : "driver";

    if (!email || !fullName) {
      return jsonResponse({ error: "email and fullName are required" }, 400);
    }

    // Only a super admin can add another dispatcher - a plain dispatcher
    // can still add drivers (checked above).
    if (role === "dispatcher" && callerProfile.role !== "super_admin") {
      return jsonResponse(
        { error: "Only a super admin can add a dispatcher" },
        403,
      );
    }

    const tempPassword = randomPassword();

    const { data: created, error: createError } = await admin.auth.admin
      .createUser({
        email,
        password: tempPassword,
        email_confirm: true,
        user_metadata: {
          full_name: fullName,
          phone,
          ghana_card_number: ghanaCardNumber,
          vehicle_number: vehicleNumber,
          must_change_password: true,
        },
      });

    if (createError) {
      return jsonResponse({ error: createError.message }, 400);
    }

    // New profiles default to "driver" (see handle_new_user()); bump it to
    // dispatcher here. This update is allowed through by
    // enforce_profile_role_change()'s service-role bypass - see migration
    // 0007_dispatcher_management.sql.
    if (role === "dispatcher") {
      const { error: roleError } = await admin
        .from("profiles")
        .update({ role: "dispatcher" })
        .eq("id", created.user!.id);
      if (roleError) {
        return jsonResponse({ error: roleError.message }, 400);
      }
    }

    const emailSent = await sendWelcomeEmail(
      email,
      fullName,
      tempPassword,
      role === "dispatcher" ? "dispatcher" : "driver",
    );

    return jsonResponse({
      userId: created.user?.id,
      tempPassword,
      emailSent,
    });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
