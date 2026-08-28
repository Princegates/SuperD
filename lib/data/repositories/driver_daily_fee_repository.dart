import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/driver_daily_fee.dart';

/// Thrown when a daily-fee action fails, with a message safe to show
/// directly to the driver or dispatcher.
class DailyFeeException implements Exception {
  DailyFeeException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DriverDailyFeeRepository {
  DriverDailyFeeRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'driver_daily_fees';

  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  /// The signed-in driver's own record for today, or null if they haven't
  /// attempted payment yet (which itself means "still unpaid" - see
  /// `driver_daily_fee_paid()` in the migration).
  Future<DriverDailyFee?> fetchToday(String driverId) async {
    final row = await _client
        .from(_table)
        .select()
        .eq('driver_id', driverId)
        .eq('fee_date', _today)
        .maybeSingle();
    return row == null ? null : DriverDailyFee.fromMap(row);
  }

  /// Live version of [fetchToday] - so a driver's "pay now" screen updates
  /// itself the moment Hubtel's webhook confirms payment, with no polling.
  Stream<DriverDailyFee?> watchToday(String driverId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('driver_id', driverId)
        .map((rows) {
          final today = _today;
          final todaysRows = rows.where((r) => r['fee_date'] == today);
          return todaysRows.isEmpty
              ? null
              : DriverDailyFee.fromMap(todaysRows.first);
        });
  }

  /// Every daily fee record ever created - the raw data behind Console >
  /// Daily Fees.
  Future<List<DriverDailyFee>> fetchAll() async {
    final rows = await _client
        .from(_table)
        .select()
        .order('created_at', ascending: false);
    return rows.map(DriverDailyFee.fromMap).toList();
  }

  /// Starts a real-time Mobile Money charge via the
  /// `hubtel-daily-fee-charge` Edge Function - the driver approves a
  /// prompt on their phone, and the row updates itself (see [watchToday])
  /// once Hubtel's webhook resolves it.
  Future<String> chargeViaHubtel({
    required String phone,
    required String network,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'hubtel-daily-fee-charge',
        body: {'phone': phone, 'network': network},
      );
      final data = response.data as Map<String, dynamic>;
      return data['message'] as String? ??
          'Check your phone to approve the payment.';
    } on FunctionException catch (e) {
      throw DailyFeeException(_messageFrom(e));
    }
  }

  /// The driver paid the business's Mobile Money number directly, outside
  /// the app, and is submitting the transaction reference for a
  /// dispatcher/super admin to confirm.
  Future<void> submitManualPayment(String reference) async {
    try {
      await _client.rpc(
        'submit_manual_daily_fee_payment',
        params: {'p_reference': reference},
      );
    } on PostgrestException catch (e) {
      throw DailyFeeException(e.message);
    }
  }

  /// Dispatcher/super admin approves or rejects a manually-submitted
  /// payment reference.
  Future<void> confirmManualPayment({
    required String feeId,
    required bool approve,
  }) async {
    await _client.rpc(
      'set_daily_fee_status',
      params: {'p_fee_id': feeId, 'p_approve': approve},
    );
  }

  /// Dispatcher/super admin clears a driver for a day without them paying
  /// anything - see `waive_daily_fee()`.
  Future<void> waiveToday(String driverId) async {
    await _client.rpc('waive_daily_fee', params: {'p_driver_id': driverId});
  }

  /// Every driver who still owes today's fee - empty whenever the feature
  /// is off. Used to steer a dispatcher's manual assignment away from a
  /// driver the database would reject anyway (see
  /// `enforce_delivery_update()`/`enforce_delivery_insert()`).
  Future<Set<String>> fetchUnpaidDriverIdsToday() async {
    final rows = await _client.rpc('unpaid_driver_ids_today') as List;
    return rows.map((id) => id as String).toSet();
  }

  /// The signed-in driver's own banked free-day balance - see
  /// `driver_free_day_credits` in `0032_commission_free_days.sql`. 0 if
  /// they've never earned or been granted one.
  Future<int> fetchFreeDayBalance(String driverId) async {
    final row = await _client
        .from('driver_free_day_credits')
        .select('balance')
        .eq('driver_id', driverId)
        .maybeSingle();
    return (row?['balance'] as num?)?.toInt() ?? 0;
  }

  /// Live version of [fetchFreeDayBalance] - updates the moment a credit
  /// is earned, granted, or spent.
  Stream<int> watchFreeDayBalance(String driverId) {
    return _client
        .from('driver_free_day_credits')
        .stream(primaryKey: ['driver_id'])
        .eq('driver_id', driverId)
        .map(
          (rows) =>
              rows.isEmpty ? 0 : (rows.first['balance'] as num?)?.toInt() ?? 0,
        );
  }

  /// Every driver's current free-day balance - the raw data behind
  /// Console > Daily Fees' incentive section.
  Future<Map<String, int>> fetchAllFreeDayBalances() async {
    final rows = await _client.from('driver_free_day_credits').select();
    return {
      for (final r in rows)
        r['driver_id'] as String: (r['balance'] as num).toInt(),
    };
  }

  /// Proactively spends a banked credit against today's fee if the driver
  /// has one and hasn't already paid/been waived - see
  /// `claim_free_day_credit()`. Safe to call anytime (including when
  /// there's nothing to claim); called once whenever the driver's own
  /// dashboard loads, so an earned reward shows up immediately rather
  /// than only once dispatch tries to assign them something.
  Future<void> claimFreeDayIfAvailable(String driverId) async {
    await _client.rpc(
      'claim_free_day_credit',
      params: {'p_driver_id': driverId},
    );
  }

  /// Dispatcher/super admin manually awards [days] free days on top of
  /// whatever the automatic rule gives - see `grant_free_day_credits()`.
  Future<void> grantFreeDays({
    required String driverId,
    required int days,
  }) async {
    try {
      await _client.rpc(
        'grant_free_day_credits',
        params: {'p_driver_id': driverId, 'p_days': days},
      );
    } on PostgrestException catch (e) {
      throw DailyFeeException(e.message);
    }
  }

  String _messageFrom(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] is String) {
      return details['error'] as String;
    }
    return 'Something went wrong. Please try again.';
  }
}
