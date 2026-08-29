/// A notice a dispatcher/super admin posted for drivers - either a
/// broadcast (every driver sees it, e.g. a promotion) or targeted at one
/// specific driver (a direct message). See `driver_notices` in
/// `0046_driver_notices.sql`.
class DriverNotice {
  const DriverNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.isActive,
    required this.dismissedBy,
    required this.createdAt,
    this.targetDriverId,
    this.createdBy,
    this.expiresAt,
  });

  final String id;
  final String title;
  final String body;

  /// Null means every driver sees this - a broadcast. Set means only this
  /// one driver does - a direct message.
  final String? targetDriverId;

  final String? createdBy;
  final bool isActive;
  final DateTime? expiresAt;

  /// Ids of drivers who've closed this notice for themselves - only
  /// meaningful for a broadcast notice (a targeted one only ever has at
  /// most its one recipient's id here). See `dismiss_driver_notice()`.
  final List<String> dismissedBy;

  final DateTime createdAt;

  bool get isBroadcast => targetDriverId == null;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool isDismissedBy(String driverId) => dismissedBy.contains(driverId);

  factory DriverNotice.fromMap(Map<String, dynamic> map) {
    return DriverNotice(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      targetDriverId: map['target_driver_id'] as String?,
      createdBy: map['created_by'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      expiresAt: map['expires_at'] == null
          ? null
          : DateTime.parse(map['expires_at'] as String),
      dismissedBy:
          (map['dismissed_by'] as List<dynamic>?)?.cast<String>() ?? const [],
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
