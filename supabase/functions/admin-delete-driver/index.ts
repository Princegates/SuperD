// Deletes a driver's, dispatcher's, or auditor's login (and, via the profiles FK's
// "on delete cascade", their profile row too). Runs with the service-role
// key - see the note in admin-create-driver/index.ts. Deploy with
// `supabase functions deploy admin-delete-driver`.
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
    if (
      !callerProfile ||
      !["dispatcher", "super_admin"].includes(callerProfile.role)
    ) {
      return jsonResponse({ error: "Not authorized" }, 403);
    }

    const body = await req.json();
    const userId = body.userId as string | undefined;
    if (!userId) return jsonResponse({ error: "userId is required" }, 400);

    // A dispatcher/super admin can remove a driver. Only a super admin can
    // remove a dispatcher or auditor - that's Team management. A super
    // admin's own account is never removable through this function - that's
    // a bigger decision than a roster edit.
    const { data: targetProfile } = await admin
      .from("profiles")
      .select("role")
      .eq("id", userId)
      .single();
    if (!targetProfile || targetProfile.role === "super_admin") {
      return jsonResponse({ error: "That account can't be removed here" }, 400);
    }
    if (targetProfile.role !== "driver" && callerProfile.role !== "super_admin") {
      return jsonResponse(
        { error: "Only a super admin can remove a dispatcher or auditor" },
        403,
      );
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      return jsonResponse({ error: deleteError.message }, 400);
    }

    return jsonResponse({ ok: true });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
