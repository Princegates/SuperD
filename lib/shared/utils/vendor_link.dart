import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/config/env.dart';

/// The public link a vendor shares with customers - opens the delivery
/// request form for that vendor with no login required.
///
/// Prefers the explicitly configured `APP_BASE_URL` (see [Env.appBaseUrl]);
/// falls back to the browser's own origin when running as a Flutter web
/// build with no override set. Never falls back to `Uri.base.origin` on a
/// non-web build - there, the "origin" is a `file://` path or app scheme,
/// not a real address, and reading `.origin` off it throws outright.
String vendorLink(String code) {
  final base = publicBaseUrl();
  return base.isEmpty ? '/v/$code' : '$base/v/$code';
}

/// The vendor's PRIVATE "view all my orders" link - a separate secret from
/// [vendorLink] (see `vendors.orders_code` in
/// `0027_separate_vendor_orders_code.sql`). Never share this with
/// customers - anyone holding it can see every order ever placed through
/// this vendor's public link, including other customers' names, phone
/// numbers, and drop-off addresses.
String vendorOrdersLink(String ordersCode) {
  final base = publicBaseUrl();
  return base.isEmpty
      ? '/vendor-orders/$ordersCode'
      : '$base/vendor-orders/$ordersCode';
}

/// The base URL vendor/customer links are built from, or '' if none could
/// be determined - see [vendorLink].
String publicBaseUrl() {
  if (Env.appBaseUrl.isNotEmpty) {
    return Env.appBaseUrl.endsWith('/')
        ? Env.appBaseUrl.substring(0, Env.appBaseUrl.length - 1)
        : Env.appBaseUrl;
  }
  if (kIsWeb) {
    final uri = Uri.base;
    if (uri.scheme == 'http' || uri.scheme == 'https') return uri.origin;
  }
  return '';
}
