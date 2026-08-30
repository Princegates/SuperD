// Fronts submit_delivery_request() with a Cloudflare Turnstile check -
// see the README's "Public form protection" section. anon's own execute
// grant on that function is revoked in
// 0059_public_form_captcha_gate.sql, so this (running with the
// service-role key) is the only way an anonymous customer can reach it
// now. A no-op pass-through - no Turnstile check at all, same behavior
// as calling the RPC directly used to be - until TURNSTILE_SECRET_KEY is
// set; see _shared/turnstile.ts.
//
// Called by the public customer-request form - no login needed, but the
// Supabase client SDK still attaches the anon key as a bearer token,
// which satisfies this function's default JWT check (verify_jwt stays
// true, same as get-road-distance).
// Deploy with `supabase functions deploy public-submit-delivery-request`.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { verifyTurnstileToken } from "../_shared/turnstile.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
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

    const { data, error } = await admin.rpc("submit_delivery_request", {
      p_code: body?.code,
      customer_name: body?.customerName,
      customer_phone: body?.customerPhone,
      dropoff_address: body?.dropoffAddress,
      dropoff_lat: body?.dropoffLat ?? null,
      dropoff_lng: body?.dropoffLng ?? null,
      package_description: body?.packageDescription ?? null,
      road_distance_km: body?.roadDistanceKm ?? null,
      scheduled_at: body?.scheduledAt ?? null,
      customer_email: body?.customerEmail ?? null,
      p_vehicle_type_id: body?.vehicleTypeId ?? null,
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
