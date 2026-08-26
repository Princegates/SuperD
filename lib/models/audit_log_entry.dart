/// One row of the super-admin audit log - who did what, and when.
class AuditLogEntry {
  final String id;
  final String? actorName;
  final String action;
  final String entityType;
  final String? entityId;
  final String summary;
  final DateTime createdAt;

  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.entityType,
    required this.summary,
    required this.createdAt,
    this.actorName,
    this.entityId,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] as String,
      actorName: map['actor_name'] as String?,
      action: map['action'] as String? ?? '',
      entityType: map['entity_type'] as String? ?? '',
      entityId: map['entity_id'] as String?,
      summary: map['summary'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
