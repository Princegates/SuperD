import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';
import '../../models/user_role.dart';

/// Thrown when a driver-management Edge Function call fails, with a message
/// safe to show directly to the dispatcher/super admin.
class DriverManagementException implements Exception {
  DriverManagementException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  Future<Profile?> fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromMap(row);
  }

  Stream<Profile?> watchProfile(String userId) {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((rows) => rows.isEmpty ? null : Profile.fromMap(rows.first));
  }

  Future<List<Profile>> fetchDrivers() async {
    final rows = await _client
        .from('profiles')
        .select()
        .eq('role', UserRole.driver.wireValue)
        .order('full_name');
    return rows.map(Profile.fromMap).toList();
  }

  /// Every user in the system, for the super-admin Team screen.
  Future<List<Profile>> fetchAllProfiles() async {
    final rows = await _client
        .from('profiles')
        .select()
        .order('role')
        .order('full_name');
    return rows.map(Profile.fromMap).toList();
  }

  /// Changes a user's role. Only takes effect server-side if the caller is
  /// a super admin - enforced by a database trigger, not just this client.
  Future<void> updateRole({
    required String userId,
    required UserRole role,
  }) async {
    await _client
        .from('profiles')
        .update({'role': role.wireValue})
        .eq('id', userId);
  }

  /// Edits a driver's own details. A dispatcher/super admin may call this
  /// for anyone; email isn't included - changing a login's email has to go
  /// through the auth admin API, not a plain table update.
  Future<void> updateDriverDetails({
    required String userId,
    required String fullName,
    String? phone,
    String? ghanaCardNumber,
    String? vehicleNumber,
  }) async {
    await _client
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone': phone,
          'ghana_card_number': ghanaCardNumber,
          'vehicle_number': vehicleNumber,
        })
        .eq('id', userId);
  }

  /// Creates a driver's login and profile via the "admin-create-driver"
  /// Edge Function (needs the service-role key, which never ships in the
  /// app). Returns a one-time temporary password to hand to the driver -
  /// they should change it after their first sign-in.
  Future<String> createDriver({
    required String email,
    required String fullName,
    String? phone,
    String? ghanaCardNumber,
    String? vehicleNumber,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'admin-create-driver',
        body: {
          'email': email,
          'fullName': fullName,
          'phone': phone,
          'ghanaCardNumber': ghanaCardNumber,
          'vehicleNumber': vehicleNumber,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return data['tempPassword'] as String;
    } on FunctionException catch (e) {
      throw DriverManagementException(_messageFrom(e));
    }
  }

  /// Deletes a driver's login (and their profile row, via cascade) through
  /// the "admin-delete-driver" Edge Function.
  Future<void> deleteDriver(String userId) async {
    try {
      await _client.functions.invoke(
        'admin-delete-driver',
        body: {'userId': userId},
      );
    } on FunctionException catch (e) {
      throw DriverManagementException(_messageFrom(e));
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
