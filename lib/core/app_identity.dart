/// The product's name, in one place.
///
/// It was written out as a literal in a dozen widgets, which is why the
/// rename from SuperD to SuperDelivery meant hunting them down a screen at
/// a time - and why the login screen still greeted riders with the old
/// name well after everything else had changed. Interpolate this instead.
///
/// It is a `const`, so it works anywhere the literal did, including const
/// constructors and the const policy text.
const String kAppName = 'SuperDelivery';
