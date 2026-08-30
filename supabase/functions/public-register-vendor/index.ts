// Fronts register_vendor() with a Cloudflare Turnstile check - see the
// README's "Public form protection" section. anon's own execute grant on
// that function is revoked in 0059_public_form_captcha_gate.sql, so this
// (running with the service-role key) is the only way an anonymous
// vendor signup can reach it now. A no-op pass-through - no Turnstile
// check at all, same behavior as calling the RPC directly used to be -
// until TURNSTILE_SECRET_KEY is set; see _shared/turnstile.ts.
//
// Only for the PUBLIC self-signup form - a dispatcher/super admin adding
// a vendor by hand from the Console still goes through the authenticated
// `register_vendor` RPC directly (that grant is untouched), never this
// function.
//
// Called with no login, but the Supabase client SDK still attaches the
// anon key as a bearer token, which satisfies this function's default
// JWT check (verify_jwt stays true, same as get-road-distance).
// Deploy with `supabase functions deploy public-register-vendor`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { jsonResponse } from "../_shared/cors.ts";
import { verifyTurnstileToken } from "../_shared/turnstile.ts";

Deno.serve(async (req) => {
  try {
    const body = await req.json();
    const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]
      ?.trim() ?? null;

    const verified = await verifyTurnstileToken(
      body?.turnstileToken,
      clientIp,
    );
    if (!verified) {
      return jsonResponse(
        { error: "Verification failed - please try again." },
        400,
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data, error } = await admin.rpc("register_vendor", {
      vendor_name: body?.vendorName,
      zone_id: body?.zoneId ?? null,
      location_lat: body?.locationLat,
      location_lng: body?.locationLng,
      phone: body?.phone,
      email: body?.email ?? null,
      created_by: null,
      p_client_ip: clientIp,
    });

    if (error) {
      return jsonResponse({ error: error.message }, 400);
    }

    const row = Array.isArray(data) ? data[0] : data;
    return jsonResponse(row);
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
