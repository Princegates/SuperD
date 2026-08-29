import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/vehicle_type.dart';
import '../../shared/utils/resilient_stream.dart';

/// Thrown when a vehicle-type action fails, with a message safe to show
/// directly to a super admin.
class VehicleTypeException implements Exception {
  VehicleTypeException(this.message);
  final String message;

  @override
  String toString() => message;
}

class VehicleTypeRepository {
  VehicleTypeRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'vehicle_types';

  /// Every configured vehicle type, live - powers Console > Settings'
  /// editor. RLS lets any authenticated role read this (`using (true)`,
  /// same as `driver_daily_fee_tiers`), but only a super admin can write.
  Stream<List<VehicleType>> watchAll() {
    return resilientRealtimeStream(
      () => _client
          .from(_table)
          .stream(primaryKey: ['id'])
          .map((rows) => rows.map(VehicleType.fromMap).toList()),
    );
  }

  /// Same data, for an anonymous customer - the delivery request form has
  /// no session at all, so this goes through `get_vehicle_types()`
  /// (SECURITY DEFINER, granted to `anon`) rather than the table's own
  /// RLS, same "narrow RPC instead of opening RLS to anon" pattern
  /// `VendorRepository.fetchVendorByCode` uses.
  Future<List<VehicleType>> fetchAllPublic() async {
    final rows = await _client.rpc('get_vehicle_types') as List;
    return rows
        .map((row) => VehicleType.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Super-admin only - enforced by RLS.
  Future<void> addVehicleType({
    required String name,
    required double extraFee,
  }) async {
    try {
      await _client.from(_table).insert({'name': name, 'extra_fee': extraFee});
    } on PostgrestException catch (e) {
      throw VehicleTypeException(e.message);
    }
  }

  /// Super-admin only - enforced by RLS. Never touches [VehicleType.isDefault];
  /// see [setDefault] for the only safe way to change which row that is.
  Future<void> updateVehicleType({
    required String id,
    required String name,
    required double extraFee,
  }) async {
    try {
      await _client
          .from(_table)
          .update({'name': name, 'extra_fee': extraFee})
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw VehicleTypeException(e.message);
    }
  }

  /// Super-admin only. The database itself refuses to delete whichever
  /// row is currently the default (see the `before delete` trigger in
  /// `0051_vehicle_types.sql`) - [setDefault] a different one first.
  Future<void> deleteVehicleType(String id) async {
    try {
      await _client.from(_table).delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw VehicleTypeException(e.message);
    }
  }

  /// Moves the default flag to [id] - the only safe way to change it,
  /// since a plain client update risks violating the "at most one
  /// default" constraint. See `set_default_vehicle_type()`.
  Future<void> setDefault(String id) async {
    try {
      await _client.rpc(
        'set_default_vehicle_type',
        params: {'p_vehicle_type_id': id},
      );
    } on PostgrestException catch (e) {
      throw VehicleTypeException(e.message);
    }
  }
}
