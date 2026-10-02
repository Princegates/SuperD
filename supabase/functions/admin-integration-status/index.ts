// Reports whether each optional third-party integration has its secret
// configured, for Console > System Health - booleans only, never a secret
// value. Every one of these lives only as an Edge Function secret (see
// get-road-distance, the paystack-*/admin-*/notify-* functions, and
// _shared/sms.ts, _shared/turnstile.ts, _shared/fcm.ts,
// _shared/webhook_auth.ts) - nothing before this function has ever
// exposed "is X configured" to the client, so this is deliberately
// narrow: super admin only (not dispatcher, not auditor - this is infra
// recon, not an operational or audit concern), and the response body can
// never contain anything but true/false. Runs with the service-role key
// only to read its own environment and the caller's profile - never to
// touch any other data. Deploy with
// `supabase functions deploy admin-integration-status`.
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
      return jsonResponse({ error: "Not authorized" }, 403);
    }

    // Boolean(Deno.env.get(...)) only - the actual values never leave
    // this function. One entry per secret this codebase actually reads
    // (see the doc comment above for exactly where each is consumed).
    return jsonResponse({
      googleMaps: Boolean(Deno.env.get("GOOGLE_MAPS_SERVER_API_KEY")),
      paystack: Boolean(Deno.env.get("PAYSTACK_SECRET_KEY")),
      hubtel: Boolean(
        Deno.env.get("HUBTEL_CLIENT_ID") &&
          Deno.env.get("HUBTEL_CLIENT_SECRET") &&
          Deno.env.get("HUBTEL_SENDER_ID"),
      ),
      resend: Boolean(
        Deno.env.get("RESEND_API_KEY") && Deno.env.get("RESEND_FROM_EMAIL"),
      ),
      turnstile: Boolean(Deno.env.get("TURNSTILE_SECRET_KEY")),
      firebase: Boolean(Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")),
      webhookSecret: Boolean(Deno.env.get("WEBHOOK_SECRET")),
    });
  } catch (e) {
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
