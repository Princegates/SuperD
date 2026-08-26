class Zone {
  final String id;
  final String name;

  const Zone({required this.id, required this.name});

  factory Zone.fromMap(Map<String, dynamic> map) {
    return Zone(id: map['id'] as String, name: map['name'] as String);
  }
}
