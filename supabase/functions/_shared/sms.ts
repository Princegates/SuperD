// Sends an SMS via Hubtel's Quick/Simple SMS API (smsc.hubtel.com, a GET
// request with the client credentials as query parameters) - shared by
// every function that texts a customer/vendor/driver/admin. Used to be
// six identical copies of a Twilio caller (one per function); centralized
// here when the whole app switched providers, since there's no reason
// for six functions to each carry their own copy of one HTTP call, and a
// future provider swap (or a Hubtel API change) now only needs touching
// one file. See the README's "SMS notifications" section for how to get
// Hubtel credentials.
//
// This is a different, older Hubtel API than the POST/JSON one
// (sms.hubtel.com, Basic Auth, a JSON body) this function used until it
// turned out this account is only provisioned for the GET one below -
// same idea (send an SMS from a client id/secret), different transport.
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

  const url = new URL("https://smsc.hubtel.com/v1/messages/send");
  url.searchParams.set("clientid", clientId);
  url.searchParams.set("clientsecret", clientSecret);
  url.searchParams.set("from", senderId);
  url.searchParams.set("to", toNumber);
  url.searchParams.set("content", body);

  try {
    const res = await fetch(url, { method: "GET" });
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
