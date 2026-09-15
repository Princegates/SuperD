// Returns the real driving distance (km) and driving time (minutes)
// between two points via Google's
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
//
// Answers come from road_distance_cache (0094) where we already have
// them. The same corridors repeat all day in a city, and every miss is a
// billed Directions call, so the cache is about the bill rather than the
// latency. Every cache operation is best-effort: a cache that is down
// must cost money, not availability, so each one is wrapped and a failure
// just falls through to Google.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

/// Rounds a coordinate to 3dp - ~110m at Ghana's latitude. Coarse on
/// purpose, so two pickups from opposite ends of the same forecourt share
/// one cached route. See 0094_road_distance_cache.sql.
function round3(value: number) {
  return Math.round(value * 1000) / 1000;
}

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

    const key = {
      origin_lat: round3(originLat),
      origin_lng: round3(originLng),
      dest_lat: round3(destLat),
      dest_lng: round3(destLng),
    };

    // Service-role client: road_distance_cache has RLS on with no
    // policies, so nothing but this reaches it.
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const cache = supabaseUrl && serviceRoleKey
      ? createClient(supabaseUrl, serviceRoleKey)
      : null;

    if (cache) {
      try {
        const { data: hit } = await cache
          .from("road_distance_cache")
          .select("distance_km, duration_minutes, hits")
          .match(key)
          .maybeSingle();
        if (hit) {
          // Awaited, not fire-and-forget. The isolate can be torn down as
          // soon as the response goes out, which would drop a detached
          // write - and refreshed_at is not just bookkeeping, it is what
          // keeps a busy corridor from being swept at 30 days. One small
          // UPDATE against a call we just saved ~300ms on is a fair
          // trade. Still wrapped: a failed bump must not lose the answer.
          try {
            await cache
              .from("road_distance_cache")
              .update({
                hits: (hit.hits ?? 0) + 1,
                refreshed_at: new Date().toISOString(),
              })
              .match(key);
          } catch (e) {
            console.error(`get-road-distance: hit bump failed: ${e}`);
          }
          return jsonResponse({
            distanceKm: hit.distance_km,
            durationMinutes: hit.duration_minutes,
            cached: true,
          });
        }
      } catch (e) {
        // A cache that is down costs money, not availability.
        console.error(`get-road-distance: cache read failed: ${e}`);
      }
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
      // Deliberately not cached. ZERO_RESULTS would be safe to remember,
      // but OVER_QUERY_LIMIT and REQUEST_DENIED are transient or
      // configuration faults, and caching one of those would keep serving
      // "no route" for a corridor that is fine once the key is fixed.
      console.error(`get-road-distance: Directions API status ${data.status}`);
      return jsonResponse({ distanceKm: null, durationMinutes: null, cached: false });
    }

    const leg = data.routes[0]?.legs?.[0];
    const meters = leg?.distance?.value;
    if (typeof meters !== "number") {
      return jsonResponse({ distanceKm: null, durationMinutes: null });
    }

    // Directions returns the driving time in the same leg we were already
    // reading the distance from, so an ETA costs no extra call and no
    // extra quota - it was being thrown away. Rounded to the minute
    // because a courier ETA claiming seconds would be false precision.
    const seconds = leg?.duration?.value;
    const durationMinutes = typeof seconds === "number"
      ? Math.max(1, Math.round(seconds / 60))
      : null;

    const distanceKm = meters / 1000;

    if (cache) {
      try {
        // Upsert rather than insert: two quotes for the same corridor can
        // race here, and the loser must not turn into a 500.
        await cache.from("road_distance_cache").upsert({
          ...key,
          distance_km: distanceKm,
          duration_minutes: durationMinutes,
          hits: 1,
          refreshed_at: new Date().toISOString(),
        });
      } catch (e) {
        console.error(`get-road-distance: cache write failed: ${e}`);
      }
    }

    return jsonResponse({ distanceKm, durationMinutes, cached: false });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
