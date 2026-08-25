// Updates a driver's or dispatcher's sign-in email. Only a super admin may
// call this - fixing someone else's login identity is more sensitive than
// a plain roster field edit, so it's not left to a dispatcher and it needs
// the service-role key (see the note in admin-create-driver/index.ts).
// Deploy with `supabase functions deploy admin-update-email`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

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
        { error: "Only a super admin can edit someone's email" },
        403,
      );
    }

    const body = await req.json();
    const userId = body.userId as string | undefined;
    const newEmail = (body.newEmail ?? "").trim();
    if (!userId || !newEmail) {
      return jsonResponse({ error: "userId and newEmail are required" }, 400);
    }

    // Never edit a super admin's own login through this function - that's
    // a bigger decision than fixing a roster typo.
    const { data: targetProfile } = await admin
      .from("profiles")
      .select("role")
      .eq("id", userId)
      .single();
    if (!targetProfile || targetProfile.role === "super_admin") {
      return jsonResponse(
        { error: "That account's email can't be edited here" },
        400,
      );
    }

    const { error: updateAuthError } = await admin.auth.admin.updateUserById(
      userId,
      { email: newEmail, email_confirm: true },
    );
    if (updateAuthError) {
      return jsonResponse({ error: updateAuthError.message }, 400);
    }

    // auth.users.email and profiles.email are separate columns - keep the
    // denormalized copy in profiles in sync too.
    const { error: updateProfileError } = await admin
      .from("profiles")
      .update({ email: newEmail })
      .eq("id", userId);
    if (updateProfileError) {
      return jsonResponse({ error: updateProfileError.message }, 400);
    }

    return jsonResponse({ ok: true });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
