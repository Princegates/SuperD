/// One admin-defined bracket of the driver daily fee - "a driver who has
/// completed at least [minDeliveries] deliveries today owes [amount] for
/// the day". See `driver_daily_fee_tiers` in `0037_tiered_daily_fee.sql`;
/// the highest tier a driver's reached wins, and no tiers at all means the
/// whole daily-fee feature is off.
class DriverDailyFeeTier {
  final String id;
  final int minDeliveries;
  final double amount;

  const DriverDailyFeeTier({
    required this.id,
    required this.minDeliveries,
    required this.amount,
  });

  factory DriverDailyFeeTier.fromMap(Map<String, dynamic> map) {
    return DriverDailyFeeTier(
      id: map['id'] as String,
      minDeliveries: (map['min_deliveries'] as num).toInt(),
      amount: (map['amount'] as num).toDouble(),
    );
  }
}
