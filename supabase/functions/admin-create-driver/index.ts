// Creates a driver's, dispatcher's, or auditor's login + profile. Runs with the
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

    // Verify who's calling and that they're staff at all - never trust the
    // client, this check happens again here server-side. What they're
    // actually allowed to create (a driver needs manage_drivers, a
    // dispatcher/auditor needs to be a super admin) is checked below, once
    // the target role is known.
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
      !["dispatcher", "super_admin", "auditor"].includes(callerProfile.role)
    ) {
      return jsonResponse({ error: "Not authorized" }, 403);
    }

    const body = await req.json();
    const email = (body.email ?? "").trim();
    const fullName = (body.fullName ?? "").trim();
    const phone = (body.phone ?? "").trim() || null;
    const ghanaCardNumber = (body.ghanaCardNumber ?? "").trim() || null;
    const vehicleNumber = (body.vehicleNumber ?? "").trim() || null;
    const vehicleType = (body.vehicleType ?? "").trim() || null;
    const dateOfBirth = (body.dateOfBirth ?? "").trim() || null;
    const residentialAddress = (body.residentialAddress ?? "").trim() || null;
    const drivingLicenseNumber = (body.drivingLicenseNumber ?? "").trim() || null;
    const drivingLicenseExpiry = (body.drivingLicenseExpiry ?? "").trim() || null;
    const vehicleInsuranceNumber = (body.vehicleInsuranceNumber ?? "").trim() || null;
    const vehicleInsuranceExpiry = (body.vehicleInsuranceExpiry ?? "").trim() || null;
    const role = ["dispatcher", "auditor"].includes(body.role)
      ? body.role
      : "driver";

    if (!email || !fullName) {
      return jsonResponse({ error: "email and fullName are required" }, 400);
    }

    // Only a super admin can add another dispatcher or auditor - Team
    // management, never delegable. Adding a driver instead needs the
    // manage_drivers permission specifically - normally true for any
    // dispatcher/auditor (role_default_permission()), but a super admin
    // can revoke it from one specific account via Team > Permissions.
    if (role !== "driver" && callerProfile.role !== "super_admin") {
      return jsonResponse(
        { error: "Only a super admin can add a dispatcher or auditor" },
        403,
      );
    }
    if (role === "driver") {
      const { data: permitted } = await admin.rpc("has_permission", {
        p_user_id: userData.user.id,
        p_permission: "manage_drivers",
      });
      if (!permitted) {
        return jsonResponse(
          { error: "You don't have permission to add a driver" },
          403,
        );
      }
    }

    // A dispatcher's or auditor's record must include date of birth, phone,
    // and residential address - the app's form already requires these, this
    // is the server-side backstop.
    if (role !== "driver" && (!phone || !dateOfBirth || !residentialAddress)) {
      return jsonResponse(
        {
          error:
            `Phone, date of birth, and residential address are required for a ${role}`,
        },
        400,
      );
    }

    // Same backstop for a driver: date of birth, vehicle, and driving
    // licence are required going forward (see
    // 0070_driver_license_and_insurance.sql) - the app's own "Add driver"
    // form already requires these too. Vehicle insurance stays optional -
    // not every driver has a policy on file yet.
    if (
      role === "driver" &&
      (!phone || !dateOfBirth || !vehicleNumber || !vehicleType ||
        !drivingLicenseNumber || !drivingLicenseExpiry)
    ) {
      return jsonResponse(
        {
          error:
            "Phone, date of birth, vehicle details, and driving licence are all required for a driver",
        },
        400,
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
          vehicle_type: vehicleType,
          date_of_birth: dateOfBirth,
          residential_address: residentialAddress,
          driving_license_number: drivingLicenseNumber,
          driving_license_expiry: drivingLicenseExpiry,
          vehicle_insurance_number: vehicleInsuranceNumber,
          vehicle_insurance_expiry: vehicleInsuranceExpiry,
          must_change_password: true,
        },
        // Only settable server-side (never by a signing-up client) - lets
        // handle_new_user() tell an admin-vetted account apart from a
        // public driver self-signup, which starts inactive pending
        // approval. See migration 0014_driver_self_signup.sql.
        app_metadata: {
          created_by_admin: true,
        },
      });

    if (createError) {
      return jsonResponse({ error: createError.message }, 400);
    }

    // New profiles default to "driver" (see handle_new_user()); bump it to
    // dispatcher/auditor here. This update is allowed through by
    // enforce_profile_role_change()'s service-role bypass - see migration
    // 0007_dispatcher_management.sql.
    if (role !== "driver") {
      const { error: roleError } = await admin
        .from("profiles")
        .update({ role })
        .eq("id", created.user!.id);
      if (roleError) {
        return jsonResponse({ error: roleError.message }, 400);
      }
    }

    const emailSent = await sendWelcomeEmail(email, fullName, tempPassword, role);

    return jsonResponse({
      userId: created.user?.id,
      tempPassword,
      emailSent,
    });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
