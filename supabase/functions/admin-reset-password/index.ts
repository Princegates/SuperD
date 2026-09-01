// Resets a driver's, dispatcher's, or auditor's password to a new random
// temporary one - for when someone's forgotten theirs and "Forgot
// password?" isn't an option (no working email, say). Super-admin-only,
// same footing as admin-update-email - forcing someone else's login is
// more sensitive than a plain roster edit, so it's not left to a
// dispatcher/auditor even one with manage_drivers. Runs with the
// service-role key (see the note in admin-create-driver/index.ts).
// Deploy with `supabase functions deploy admin-reset-password`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

function randomPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return btoa(String.fromCharCode(...bytes))
    .replace(/[^a-zA-Z0-9]/g, "")
    .slice(0, 12);
}

// Same approach as admin-create-driver's sendWelcomeEmail - Resend's HTTP
// API, never throws (a failed/unconfigured send still leaves the reset
// itself successful, with tempPassword returned as a fallback to share by
// hand).
async function sendResetEmail(
  email: string,
  fullName: string,
  tempPassword: string,
): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.error("sendResetEmail: RESEND_API_KEY is not set");
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
        subject: "Your SuperD password was reset",
        html: `
          <p>Hi ${fullName},</p>
          <p>A super admin reset your SuperD account password.</p>
          <p><strong>Temporary password:</strong> ${tempPassword}</p>
          <p>Sign in with this in the SuperD app. You'll be asked to set
          your own password before you can do anything else. If you didn't
          expect this, contact your dispatcher/super admin.</p>
        `,
      }),
    });
    if (!res.ok) {
      console.error(
        `sendResetEmail: Resend responded ${res.status} - ${await res.text()}`,
      );
    }
    return res.ok;
  } catch (e) {
    console.error("sendResetEmail: fetch to Resend failed -", e);
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
    if (!callerProfile || callerProfile.role !== "super_admin") {
      return jsonResponse(
        { error: "Only a super admin can reset someone's password" },
        403,
      );
    }

    const body = await req.json();
    const userId = body.userId as string | undefined;
    if (!userId) return jsonResponse({ error: "userId is required" }, 400);

    // Never reset a super admin's own login through this function - that's
    // a bigger decision than fixing someone's forgotten password, same
    // reasoning as admin-update-email/admin-delete-driver.
    const { data: targetProfile } = await admin
      .from("profiles")
      .select("email, full_name, role")
      .eq("id", userId)
      .single();
    if (!targetProfile || targetProfile.role === "super_admin") {
      return jsonResponse(
        { error: "That account's password can't be reset here" },
        400,
      );
    }

    const tempPassword = randomPassword();

    const { error: updateAuthError } = await admin.auth.admin.updateUserById(
      userId,
      { password: tempPassword },
    );
    if (updateAuthError) {
      return jsonResponse({ error: updateAuthError.message }, 400);
    }

    // Forces the mandatory "Change password" screen on next sign-in, same
    // as a brand-new account - see 0005_driver_password_reset.sql.
    const { error: updateProfileError } = await admin
      .from("profiles")
      .update({ must_change_password: true })
      .eq("id", userId);
    if (updateProfileError) {
      return jsonResponse({ error: updateProfileError.message }, 400);
    }

    const emailSent = await sendResetEmail(
      targetProfile.email,
      targetProfile.full_name,
      tempPassword,
    );

    return jsonResponse({ tempPassword, emailSent });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
