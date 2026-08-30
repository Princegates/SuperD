// Push notifications via Firebase Cloud Messaging's HTTP v1 API. Needs a
// Firebase service account with the "Firebase Cloud Messaging API" role -
// see the README's "Push notifications" section for how to create one and
// set FIREBASE_SERVICE_ACCOUNT_JSON. Every function below degrades to a
// no-op (logs and returns false/0) when that secret isn't set, same as
// every other optional integration in this codebase (Twilio, Resend,
// Google Directions) - so nothing breaks for a project that hasn't set
// push up yet.
//
// v1 needs a short-lived OAuth2 access token, not a static server key
// (the old legacy HTTP API Google has been sunsetting) - this signs the
// service account's own JWT with Web Crypto (RS256) and exchanges it at
// Google's token endpoint, rather than pulling in a full auth library
// for one request.

function base64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function readServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!raw) {
    console.error("fcm: FIREBASE_SERVICE_ACCOUNT_JSON is not set");
    return null;
  }
  try {
    return JSON.parse(raw) as ServiceAccount;
  } catch (e) {
    console.error("fcm: FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON -", e);
    return null;
  }
}

async function getAccessToken(sa: ServiceAccount): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${
    base64url(JSON.stringify(claims))
  }`;

  const pemBody = sa.private_key
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  let cryptoKey: CryptoKey;
  try {
    cryptoKey = await crypto.subtle.importKey(
      "pkcs8",
      keyBytes,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    );
  } catch (e) {
    console.error("fcm: could not import service account private key -", e);
    return null;
  }

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(signature)}`;

  try {
    const res = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    });
    if (!res.ok) {
      console.error(
        `fcm: token exchange failed ${res.status} - ${await res.text()}`,
      );
      return null;
    }
    const data = await res.json();
    return data.access_token as string;
  } catch (e) {
    console.error("fcm: fetch to oauth2.googleapis.com failed -", e);
    return null;
  }
}

/// Sends one push message to a single FCM registration token. Returns
/// false (never throws) on any failure - a missing/invalid/expired token,
/// missing credentials, or an FCM-side error - so a caller looping over
/// several of a profile's devices can just keep going.
export async function sendPush(
  token: string,
  title: string,
  body: string,
  data?: Record<string, string>,
): Promise<boolean> {
  const sa = readServiceAccount();
  if (!sa) return false;

  const accessToken = await getAccessToken(sa);
  if (!accessToken) return false;

  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: { token, notification: { title, body }, data: data ?? {} },
        }),
      },
    );
    if (!res.ok) {
      console.error(`fcm: send failed ${res.status} - ${await res.text()}`);
    }
    return res.ok;
  } catch (e) {
    console.error("fcm: fetch to fcm.googleapis.com failed -", e);
    return false;
  }
}

/// Pushes to every device currently registered to a profile (see
/// device_push_tokens in 0057_device_push_tokens.sql) - a signed-in user
/// can have more than one (a driver's phone and tablet, say). Takes an
/// already-created service-role client, same as every other admin-*/
/// notify-* function's helpers. Returns how many of the profile's
/// devices the push actually reached.
export async function sendPushToProfile(
  // deno-lint-ignore no-explicit-any
  admin: any,
  profileId: string,
  title: string,
  body: string,
  data?: Record<string, string>,
): Promise<number> {
  const { data: rows, error } = await admin
    .from("device_push_tokens")
    .select("token")
    .eq("profile_id", profileId);
  if (error || !rows) return 0;

  let sent = 0;
  for (const row of rows) {
    if (await sendPush(row.token as string, title, body, data)) sent++;
  }
  return sent;
}
