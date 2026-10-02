/// One action's rate-limit hit volume - see
/// `get_rate_limit_summary()` in `0096_rate_limit_and_cache_admin_stats.sql`.
class RateLimitSummaryRow {
  const RateLimitSummaryRow({
    required this.action,
    required this.hitsLastHour,
    required this.hitsLast24h,
  });

  final String action;
  final int hitsLastHour;
  final int hitsLast24h;

  factory RateLimitSummaryRow.fromMap(Map<String, dynamic> map) {
    return RateLimitSummaryRow(
      action: map['action'] as String? ?? '',
      hitsLastHour: (map['hits_last_hour'] as num?)?.toInt() ?? 0,
      hitsLast24h: (map['hits_last_24h'] as num?)?.toInt() ?? 0,
    );
  }
}

/// How well the road-distance cache is earning its keep - see
/// `get_road_distance_cache_stats()` in
/// `0096_rate_limit_and_cache_admin_stats.sql`.
class RoadDistanceCacheStats {
  const RoadDistanceCacheStats({
    required this.totalRoutes,
    required this.routesAddedLast24h,
    required this.totalHits,
    required this.avgHitsPerRoute,
  });

  final int totalRoutes;
  final int routesAddedLast24h;
  final int totalHits;
  final double avgHitsPerRoute;

  static const empty = RoadDistanceCacheStats(
    totalRoutes: 0,
    routesAddedLast24h: 0,
    totalHits: 0,
    avgHitsPerRoute: 0,
  );

  factory RoadDistanceCacheStats.fromMap(Map<String, dynamic> map) {
    return RoadDistanceCacheStats(
      totalRoutes: (map['total_routes'] as num?)?.toInt() ?? 0,
      routesAddedLast24h: (map['routes_added_last_24h'] as num?)?.toInt() ?? 0,
      totalHits: (map['total_hits'] as num?)?.toInt() ?? 0,
      avgHitsPerRoute: (map['avg_hits_per_route'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Whether each optional third-party integration's secret is configured -
/// booleans only, from the `admin-integration-status` Edge Function. Keys
/// match that function's response exactly.
class IntegrationStatus {
  const IntegrationStatus({
    required this.googleMaps,
    required this.paystack,
    required this.hubtel,
    required this.resend,
    required this.turnstile,
    required this.firebase,
    required this.webhookSecret,
  });

  final bool googleMaps;
  final bool paystack;
  final bool hubtel;
  final bool resend;
  final bool turnstile;
  final bool firebase;
  final bool webhookSecret;

  factory IntegrationStatus.fromMap(Map<String, dynamic> map) {
    return IntegrationStatus(
      googleMaps: map['googleMaps'] as bool? ?? false,
      paystack: map['paystack'] as bool? ?? false,
      hubtel: map['hubtel'] as bool? ?? false,
      resend: map['resend'] as bool? ?? false,
      turnstile: map['turnstile'] as bool? ?? false,
      firebase: map['firebase'] as bool? ?? false,
      webhookSecret: map['webhookSecret'] as bool? ?? false,
    );
  }

  /// (label, isConfigured, what breaks if it's off) - what
  /// `ConsoleSystemHealthTab` actually renders, one row per entry.
  List<(String, bool, String)> get rows => [
    (
      'Google Maps',
      googleMaps,
      'Road-distance pricing/ETA falls back to straight-line distance',
    ),
    (
      'Paystack',
      paystack,
      'Drivers/vendors can only pay via a dispatcher-confirmed manual reference',
    ),
    ('Hubtel (SMS)', hubtel, 'Tracking links and notices stop sending by SMS'),
    ('Resend (email)', resend, 'Account and notification emails stop sending'),
    (
      'Cloudflare Turnstile',
      turnstile,
      'The two public forms accept submissions with no CAPTCHA check',
    ),
    ('Firebase (push)', firebase, 'Push notifications are a no-op'),
    (
      'Webhook secret',
      webhookSecret,
      'Database-triggered notifications fail closed until this is set',
    ),
  ];
}
