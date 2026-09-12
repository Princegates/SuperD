// Escaping for the HTML emails these functions send.
//
// Names, addresses, package descriptions and business names all reach an
// email body from somewhere a stranger can type into - the public customer
// request form and the public vendor signup form especially. Interpolated
// raw, a customer name of
//   Ama <a href="https://not-superd.example/pay">Pay here</a>
// renders as a working link in the dispatcher's and vendor's inbox, on an
// email that genuinely came from this app's own domain. That's a phishing
// vector, not a cosmetic bug.
//
// Used as a tagged template so escaping is the default rather than
// something each call site has to remember:
//
//   html`<p>Hi ${customerName},</p>`
//
// Values are escaped; the literal markup around them isn't. To deliberately
// include markup built elsewhere (a block of rows assembled with `html`
// already), wrap it in `raw()`.

export class RawHtml {
  constructor(readonly value: string) {}
  toString(): string {
    return this.value;
  }
}

/// Marks an already-escaped/trusted fragment so `html` won't escape it
/// again - e.g. a list of rows built with `html` in a loop and joined.
export function raw(value: string): RawHtml {
  return new RawHtml(value);
}

export function escapeHtml(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (value instanceof RawHtml) return value.value;
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function html(
  strings: TemplateStringsArray,
  ...values: unknown[]
): string {
  return strings.reduce(
    (out, chunk, i) =>
      out + chunk + (i < values.length ? escapeHtml(values[i]) : ""),
    "",
  );
}
