/// The public link a vendor shares with customers - opens the delivery
/// request form for that vendor with no login required. Built off the
/// current origin, so it always points at wherever this instance is
/// actually hosted.
String vendorLink(String code) => '${Uri.base.origin}/v/$code';
