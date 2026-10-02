// Resolves a place_id from google-places-autocomplete into coordinates,
// via Google's Places API (New) Place Details endpoint - the second half
// of that function's Autocomplete-then-Details split (see its comment on
// session tokens). Called once, when the customer/vendor actually taps a
// suggestion, not per keystroke.
//
// The key lives ONLY here, server-side, as a secret - same
// GOOGLE_MAPS_SERVER_API_KEY as get-road-distance and
// google-places-autocomplete.
// Deploy with `supabase functions deploy google-place-details`.
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
    const placeId = typeof body?.placeId === "string" ? body.placeId : "";
    const sessionToken = typeof body?.sessionToken === "string"
      ? body.sessionToken
      : undefined;
    if (!placeId) {
      return jsonResponse({ error: "placeId is required" }, 400);
    }

    const url = new URL(
      `https://places.googleapis.com/v1/places/${placeId}`,
    );
    if (sessionToken) url.searchParams.set("sessionToken", sessionToken);

    const res = await fetch(url, {
      headers: {
        "X-Goog-Api-Key": apiKey,
        // Location only - the cheapest Place Details tier, and the only
        // field the map pin actually needs.
        "X-Goog-FieldMask": "location",
      },
    });

    if (!res.ok) {
      const errText = await res.text();
      console.error(`google-place-details: Places API ${res.status}: ${errText}`);
      return jsonResponse({ lat: null, lng: null });
    }

    const data = await res.json();
    const lat = data?.location?.latitude;
    const lng = data?.location?.longitude;
    if (typeof lat !== "number" || typeof lng !== "number") {
      return jsonResponse({ lat: null, lng: null });
    }

    return jsonResponse({ lat, lng });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
