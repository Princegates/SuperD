// Sends an SMS via Hubtel's REST API - shared by every function that
// texts a customer/vendor/driver/admin. Used to be six identical copies
// of a Twilio caller (one per function); centralized here when the whole
// app switched providers, since there's no reason for six functions to
// each carry their own copy of one HTTP call, and a future provider swap
// (or a Hubtel API change) now only needs touching one file. See the
// README's "SMS notifications" section for how to get Hubtel credentials.
export async function sendSms(to: string, body: string): Promise<boolean> {
  const clientId = Deno.env.get("HUBTEL_CLIENT_ID");
  const clientSecret = Deno.env.get("HUBTEL_CLIENT_SECRET");
  const senderId = Deno.env.get("HUBTEL_SENDER_ID");
  if (!clientId || !clientSecret || !senderId) {
    console.error("sendSms: Hubtel secrets are not fully set");
    return false;
  }

  // Hubtel expects a Ghanaian number in international format WITHOUT the
  // leading "+" (e.g. 233241234567). Every number in this app is stored
  // as +233XXXXXXXXX (see lib/shared/utils/ghana_phone.dart) - stripped
  // here rather than at every call site.
  const toNumber = to.replace(/^\+/, "");

  try {
    const res = await fetch("https://sms.hubtel.com/v1/messages/send", {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ From: senderId, To: toNumber, Content: body }),
    });
    if (!res.ok) {
      console.error(
        `sendSms: Hubtel responded ${res.status} - ${await res.text()}`,
      );
    }
    return res.ok;
  } catch (e) {
    console.error("sendSms: fetch to Hubtel failed -", e);
    return false;
  }
}
