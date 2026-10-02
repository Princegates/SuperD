// Address suggestions as someone types, via Google's Places API (New)
// Autocomplete endpoint - the paid alternative to the free
// searchAddress()/Nominatim path in lib/shared/utils/geocode_search.dart.
// Called from the vendor signup form and the customer request form, both
// public with no login - the Supabase client SDK still attaches the anon
// key as a bearer token, which satisfies this function's default JWT
// check (verify_jwt stays true; see get-road-distance's comment on why
// the notify-*/admin-* functions need to override that - this one
// doesn't).
//
// The key lives ONLY here, server-side, as a secret - never shipped to
// any client build, same reasoning as GOOGLE_MAPS_SERVER_API_KEY in
// get-road-distance (this reuses that same secret; Places and Directions
// are billed on the same key/project).
// Deploy with `supabase functions deploy google-places-autocomplete`.
//
// Returns only place descriptions + place IDs - never coordinates. Places
// API (New) deliberately splits Autocomplete from Place Details so a
// session token can carry a whole typing sequence through to one Details
// call (google-place-details) for a single session charge instead of
// billing each keystroke's request separately - see
// developers.google.com/maps/documentation/places/web-service/session-pricing.
// The client is responsible for minting one token per search and reusing
// it across every request in that sequence (AddressAutocompleteField's
// _sessionToken).
import { createClient } from "jsr:@supabase/supabase-js@2";
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
    const query = typeof body?.query === "string" ? body.query.trim() : "";
    const sessionToken = typeof body?.sessionToken === "string"
      ? body.sessionToken
      : undefined;
    if (query.length < 3) {
      return jsonResponse({ suggestions: [] });
    }

    // Billed per keystroke (or per session), unlike get-road-distance's
    // one-call-per-pin-drop, so this is the one Google proxy here that
    // needs its own throttle rather than riding on a caller's existing
    // one - the debounce in AddressAutocompleteField keeps a normal typist
    // well under this; it's here for whatever bypasses that debounce.
    // Generous per-search-session budget (~20 typed addresses), not
    // per-keystroke, since a real search is several keystrokes.
    const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]
      ?.trim();
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (clientIp && supabaseUrl && serviceRoleKey) {
      const db = createClient(supabaseUrl, serviceRoleKey);
      const { error: rateLimitError } = await db.rpc("enforce_rate_limit", {
        p_key: `ip:${clientIp}`,
        p_action: "google_places_autocomplete",
        p_max_count: 120,
        p_window: "10 minutes",
      });
      if (rateLimitError) {
        console.error(
          `google-places-autocomplete: rate limited: ${rateLimitError.message}`,
        );
        return jsonResponse({ suggestions: [] });
      }
    }

    const res = await fetch(
      "https://places.googleapis.com/v1/places:autocomplete",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey,
          // Only the field this response actually reads - Autocomplete
          // (New) is priced flat regardless of field mask, but this keeps
          // the payload (and Google's work generating it) to what's used.
          "X-Goog-FieldMask":
            "suggestions.placePrediction.place,suggestions.placePrediction.placeId,suggestions.placePrediction.text",
        },
        body: JSON.stringify({
          input: query,
          sessionToken,
          // Ghana only - SuperD doesn't operate anywhere else, and this
          // keeps a Ghanaian street name from losing to a same-named
          // place abroad.
          includedRegionCodes: ["gh"],
        }),
      },
    );

    if (!res.ok) {
      const errText = await res.text();
      console.error(
        `google-places-autocomplete: Places API ${res.status}: ${errText}`,
      );
      // Fail soft - same posture as get-road-distance: a bad key or quota
      // hit degrades the feature, it doesn't break the form.
      return jsonResponse({ suggestions: [] });
    }

    const data = await res.json();
    const suggestions = (data.suggestions ?? [])
      .map((s: Record<string, unknown>) => {
        const prediction = s.placePrediction as
          | Record<string, unknown>
          | undefined;
        const text = prediction?.text as Record<string, unknown> | undefined;
        const description = text?.text;
        const placeId = prediction?.placeId;
        if (typeof description !== "string" || typeof placeId !== "string") {
          return null;
        }
        return { description, placeId };
      })
      .filter((s: unknown) => s !== null);

    return jsonResponse({ suggestions });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
