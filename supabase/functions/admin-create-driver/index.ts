// Creates a driver's login + profile. Runs with the service-role key, which
// must never be shipped inside the app - this is the one place that key is
// allowed to live. Deploy with `supabase functions deploy admin-create-driver`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

function randomPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return btoa(String.fromCharCode(...bytes))
    .replace(/[^a-zA-Z0-9]/g, "")
    .slice(0, 12);
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

    if (!email || !fullName) {
      return jsonResponse({ error: "email and fullName are required" }, 400);
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
        },
      });

    if (createError) {
      return jsonResponse({ error: createError.message }, 400);
    }

    return jsonResponse({
      userId: created.user?.id,
      tempPassword,
    });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : String(e) }, 500);
  }
});
