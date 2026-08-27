// Returns the real driving distance (km) between two points via Google's
// Directions API, for delivery pricing (see submit_delivery_request /
// get_delivery_price_estimate in 0028_road_distance_pricing.sql). Called
// directly by the customer request form - no login needed, but the
// Supabase client SDK still attaches the anon key as a bearer token, which
// satisfies this function's default JWT check (verify_jwt stays true;
// see supabase/config.toml's comment on why the notify-*/admin-* functions
// need to override that - this one doesn't).
//
// The Directions API key lives ONLY here, server-side, as a secret - never
// shipped to any client build. This is deliberately a separate key from
// the Maps SDK/JS keys baked into the Android/iOS/web builds (see the
// README's "Google Maps setup" and "Road-distance pricing" sections):
// those are locked down by platform/referrer restriction, which doesn't
// reliably apply to a plain server-side HTTP call the way it does to
// Google's own SDKs.
// Deploy with `supabase functions deploy get-road-distance`, and set the
// key first: `supabase secrets set GOOGLE_MAPS_SERVER_API_KEY=...`
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const apiKey = Deno.env.get("GOOGLE_MAPS_SERVER_API_KEY");
    if (!apiKey) {
      return jsonResponse(
        { error: "GOOGLE_MAPS_SERVER_API_KEY is not configured" },
        500,
      );
    }

    const body = await req.json();
    const originLat = Number(body?.originLat);
    const originLng = Number(body?.originLng);
    const destLat = Number(body?.destLat);
    const destLng = Number(body?.destLng);
    if (
      !Number.isFinite(originLat) || !Number.isFinite(originLng) ||
      !Number.isFinite(destLat) || !Number.isFinite(destLng)
    ) {
      return jsonResponse({ error: "Invalid coordinates" }, 400);
    }

    const url = new URL("https://maps.googleapis.com/maps/api/directions/json");
    url.searchParams.set("origin", `${originLat},${originLng}`);
    url.searchParams.set("destination", `${destLat},${destLng}`);
    url.searchParams.set("mode", "driving");
    url.searchParams.set("key", apiKey);

    const res = await fetch(url);
    const data = await res.json();

    if (data.status !== "OK" || !data.routes?.length) {
      // No route (e.g. across water), a bad key, or Google's quota hit -
      // fail soft. The caller falls back to straight-line distance, same
      // as before this feature existed.
      console.error(`get-road-distance: Directions API status ${data.status}`);
      return jsonResponse({ distanceKm: null });
    }

    const meters = data.routes[0]?.legs?.[0]?.distance?.value;
    if (typeof meters !== "number") {
      return jsonResponse({ distanceKm: null });
    }

    return jsonResponse({ distanceKm: meters / 1000 });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
