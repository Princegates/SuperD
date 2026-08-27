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

  /// Every driver, live - for the dispatcher/super-admin Live Map. Filtering
  /// out stale positions (a driver who closed the app a while ago) happens
  /// client-side via `Profile.hasRecentLocation`, since this just streams
  /// the raw rows.
  Stream<List<Profile>> watchDriverLocations() {
    return _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('role', UserRole.driver.wireValue)
        .order('full_name')
        .map((rows) => rows.map(Profile.fromMap).toList());
  }

  /// Called every ~15s by a driver's own app, only while it's open and
  /// location is granted - see DriverDashboardScreen. No background
  /// tracking; the position just goes stale (and drops off the Live Map)
  /// once updates stop.
  Future<void> updateLiveLocation({
    required String userId,
    required double lat,
    required double lng,
  }) async {
    await _client
        .from('profiles')
        .update({
          'last_lat': lat,
          'last_lng': lng,
          'location_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
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

  /// Approves a self-signed-up driver (or deactivates any staff member) by
  /// flipping `is_active`. A driver can't be assigned deliveries while
  /// inactive - see `rankedDriversProvider` - and the app itself keeps them
  /// on a "pending approval" screen until this is set to true.
  Future<void> setActive(String userId, bool isActive) async {
    await _client
        .from('profiles')
        .update({'is_active': isActive})
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
    DateTime? dateOfBirth,
    String? residentialAddress,
    String? zoneId,
  }) async {
    await _client
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone': phone,
          'ghana_card_number': ghanaCardNumber,
          'vehicle_number': vehicleNumber,
          'date_of_birth': _dateOnly(dateOfBirth),
          'residential_address': residentialAddress,
          'zone_id': zoneId,
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
    String? residentialAddress,
  }) => _createStaffAccount(
    role: UserRole.driver,
    email: email,
    fullName: fullName,
    phone: phone,
    ghanaCardNumber: ghanaCardNumber,
    vehicleNumber: vehicleNumber,
    residentialAddress: residentialAddress,
  );

  /// Creates a dispatcher's login and profile via the same Edge Function.
  /// Only a super admin may call this - enforced server-side too.
  Future<({String tempPassword, bool emailSent})> createDispatcher({
    required String email,
    required String fullName,
    required String phone,
    required DateTime dateOfBirth,
    required String residentialAddress,
  }) => _createStaffAccount(
    role: UserRole.dispatcher,
    email: email,
    fullName: fullName,
    phone: phone,
    dateOfBirth: dateOfBirth,
    residentialAddress: residentialAddress,
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
    DateTime? dateOfBirth,
    String? residentialAddress,
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
          'dateOfBirth': _dateOnly(dateOfBirth),
          'residentialAddress': residentialAddress,
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

  String? _dateOnly(DateTime? date) => date?.toIso8601String().substring(0, 10);

  /// Clears the "must change password" flag once the user has set their
  /// own password after first sign-in. Reads the row back (`.select()`) so
  /// a silent no-op - e.g. an RLS policy quietly matching zero rows, which
  /// a plain `.update()` wouldn't otherwise surface as an error - throws
  /// instead of leaving the caller to loop forever on the mandatory screen.
  Future<void> clearMustChangePassword(String userId) async {
    final rows = await _client
        .from('profiles')
        .update({'must_change_password': false})
        .eq('id', userId)
        .select();
    if (rows.isEmpty) {
      throw StateError(
        "Couldn't confirm the password-change flag was cleared for "
        '$userId - no row was updated.',
      );
    }
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

  /// Fixes a driver's or dispatcher's sign-in email via the
  /// "admin-update-email" Edge Function. Only a super admin may call this -
  /// enforced server-side too - since it changes someone else's login
  /// identity, not just a roster field.
  Future<void> updateEmail({
    required String userId,
    required String newEmail,
  }) async {
    try {
      await _client.functions.invoke(
        'admin-update-email',
        body: {'userId': userId, 'newEmail': newEmail},
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
