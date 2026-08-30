// Verifies a Cloudflare Turnstile token server-side - see the README's
// "Public form protection" section. A no-op (returns true, no request to
// Cloudflare at all) when TURNSTILE_SECRET_KEY isn't set, same as every
// other optional integration in this codebase - a project that hasn't
// set up Turnstile yet isn't blocked from using the two public forms at
// all, it's exactly as open as it was before this existed.
export async function verifyTurnstileToken(
  token: string | null | undefined,
  remoteIp?: string | null,
): Promise<boolean> {
  const secretKey = Deno.env.get("TURNSTILE_SECRET_KEY");
  if (!secretKey) return true;

  if (!token) {
    console.error("verifyTurnstileToken: no token provided");
    return false;
  }

  try {
    const body = new URLSearchParams({ secret: secretKey, response: token });
    if (remoteIp) body.set("remoteip", remoteIp);

    const res = await fetch(
      "https://challenges.cloudflare.com/turnstile/v0/siteverify",
      { method: "POST", body },
    );
    const data = await res.json();
    if (!data.success) {
      console.error(
        `verifyTurnstileToken: verification failed - ${
          JSON.stringify(data["error-codes"])
        }`,
      );
    }
    return Boolean(data.success);
  } catch (e) {
    console.error("verifyTurnstileToken: fetch to Cloudflare failed -", e);
    return false;
  }
}
