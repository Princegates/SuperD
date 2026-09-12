// Shared secret for the notify-* functions, which run with verify_jwt =
// false (see supabase/config.toml) because they're called by this
// project's own database webhooks, and the pg_net fallback route the
// README documents has no clean way to attach a platform JWT.
//
// Each of those functions re-fetches everything it sends fresh from the
// database by id, so a forged payload can't put made-up content in a
// message. What that doesn't stop is replay: without this check anyone on
// the internet who can guess or observe a delivery id can POST it back
// repeatedly and make the app text and email the real customer, vendor and
// dispatchers on file - every SMS billed to the business's own Twilio
// account, and every message landing on a real person's phone. The id
// being a UUID slows that down; it isn't an access control.
//
// Set the secret once:
//   supabase secrets set WEBHOOK_SECRET="$(openssl rand -hex 32)"
// then add `x-webhook-secret: <that value>` as a header on each Database
// Webhook (Database -> Webhooks in the dashboard), or to the headers jsonb
// in the pg_net trigger version. See the README.
//
// Deliberately fails closed when WEBHOOK_SECRET is unset: an unset secret
// is exactly the state this is meant to catch, and the alternative -
// quietly accepting everything, the way this codebase treats an
// unconfigured Twilio or Firebase - would leave the hole open on precisely
// the deployments that never got around to setting it.

/// Length-independent, constant-time-ish comparison. Not strictly required
/// for a header check (an attacker can't iterate a remote timing side
/// channel cheaply here), but it costs nothing and keeps the comparison
/// from short-circuiting on the first differing byte.
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  // Compare a fixed number of bytes either way, so length alone doesn't
  // decide how long this takes.
  let diff = ab.length ^ bb.length;
  const len = Math.max(ab.length, bb.length);
  for (let i = 0; i < len; i++) {
    diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  }
  return diff === 0;
}

/// Returns null when the caller presented the right secret, or a Response
/// to return as-is when it didn't:
///
///   const denied = verifyWebhookSecret(req);
///   if (denied) return denied;
export function verifyWebhookSecret(req: Request): Response | null {
  const expected = Deno.env.get("WEBHOOK_SECRET");
  if (!expected) {
    console.error(
      "WEBHOOK_SECRET is not set - refusing the request. Set it with " +
        "`supabase secrets set WEBHOOK_SECRET=...` and add a matching " +
        "x-webhook-secret header to this function's database webhook.",
    );
    return new Response(
      JSON.stringify({ error: "Webhook authentication is not configured" }),
      { status: 503, headers: { "Content-Type": "application/json" } },
    );
  }

  const provided = req.headers.get("x-webhook-secret");
  if (!provided || !timingSafeEqual(provided, expected)) {
    return new Response(
      JSON.stringify({ error: "Not authorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  return null;
}
