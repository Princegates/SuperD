import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';
import '../../models/user_role.dart';

/// Thrown when a staff-management Edge Function call fails, with a message
/// safe to show directly to the dispatcher/super admin.
class StaffManagementException implements Exception {
  StaffManagementException(this.message);
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

  /// Edits a driver's or dispatcher's own details. A dispatcher/super admin
  /// may call this for anyone; email isn't included - changing a login's
  /// email has to go through the auth admin API, not a plain table update.
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
  /// Edge Function. Callable by a dispatcher or super admin.
  Future<({String tempPassword, bool emailSent})> createDriver({
    required String email,
    required String fullName,
    String? phone,
    String? ghanaCardNumber,
    String? vehicleNumber,
  }) => _createStaffAccount(
    role: UserRole.driver,
    email: email,
    fullName: fullName,
    phone: phone,
    ghanaCardNumber: ghanaCardNumber,
    vehicleNumber: vehicleNumber,
  );

  /// Creates a dispatcher's login and profile via the same Edge Function.
  /// Only a super admin may call this - enforced server-side too.
  Future<({String tempPassword, bool emailSent})> createDispatcher({
    required String email,
    required String fullName,
    String? phone,
  }) => _createStaffAccount(
    role: UserRole.dispatcher,
    email: email,
    fullName: fullName,
    phone: phone,
  );

  /// Creates a login + profile via the "admin-create-driver" Edge Function
  /// (needs the service-role key, which never ships in the app). The new
  /// user is emailed their temporary password directly and must set their
  /// own on first sign-in; [tempPassword] is still returned as a fallback
  /// to share by hand if [emailSent] is false.
  Future<({String tempPassword, bool emailSent})> _createStaffAccount({
    required UserRole role,
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
          'role': role.wireValue,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return (
        tempPassword: data['tempPassword'] as String,
        emailSent: data['emailSent'] as bool? ?? false,
      );
    } on FunctionException catch (e) {
      throw StaffManagementException(_messageFrom(e));
    }
  }

  /// Clears the "must change password" flag once the user has set their
  /// own password after first sign-in.
  Future<void> clearMustChangePassword(String userId) async {
    await _client
        .from('profiles')
        .update({'must_change_password': false})
        .eq('id', userId);
  }

  /// Deletes a driver's or dispatcher's login (and their profile row, via
  /// cascade) through the "admin-delete-driver" Edge Function. Removing a
  /// dispatcher requires the caller to be a super admin - enforced
  /// server-side, based on the target's actual role.
  Future<void> deleteStaffAccount(String userId) async {
    try {
      await _client.functions.invoke(
        'admin-delete-driver',
        body: {'userId': userId},
      );
    } on FunctionException catch (e) {
      throw StaffManagementException(_messageFrom(e));
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
