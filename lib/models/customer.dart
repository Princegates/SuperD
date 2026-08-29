/// One row per customer, keyed by phone - name/email/last-known drop-off
/// address, kept current automatically as new deliveries come in. Super
/// admin only - see `customers` in `0055_customer_directory.sql`; a
/// dispatcher or auditor never sees this, only whatever's on an individual
/// delivery they already have access to.
class Customer {
  const Customer({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.address,
  });

  final String id;
  final String phone;
  final String fullName;
  final String? email;

  /// The drop-off address from this customer's most recent delivery - not
  /// necessarily a permanent home address, just the latest one on file.
  final String? address;

  final DateTime createdAt;
  final DateTime updatedAt;

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as String,
      phone: map['phone'] as String,
      fullName: map['full_name'] as String,
      email: map['email'] as String?,
      address: map['address'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
