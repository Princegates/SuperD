import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/driver_vehicle_type.dart';
import '../../models/profile.dart';
import '../../models/staff_permission.dart';
import '../../models/user_role.dart';
import '../../shared/utils/resilient_stream.dart';

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
    return resilientRealtimeStream(
      () => _client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', userId)
          .map((rows) => rows.isEmpty ? null : Profile.fromMap(rows.first)),
    );
  }

  /// Bucket holding rider photographs. Private, unlike proof-of-delivery -
  /// see `0091_rider_photo.sql` - so nothing here is reachable by URL
  /// alone; every read goes through a signed link.
  static const _photoBucket = 'rider-photos';

  /// Stores a rider's photograph and points their profile at it.
  ///
  /// [bytes] must already be through [RiderPhoto.compress]; this does not
  /// check the size, because by the time it gets here the rider has been
  /// waiting on an upload and refusing it would be too late to be useful.
  ///
  /// `upsert` so a retake during signup replaces the file rather than
  /// leaving the previous attempt behind. The database decides whether a
  /// retake is allowed at all - both the storage policy and the profile
  /// trigger close it off once the rider is approved - so a refusal here
  /// surfaces as a StorageException, not as a silently ignored write.
  Future<String> uploadRiderPhoto({
    required String userId,
    required Uint8List bytes,
  }) async {
    final path = '$userId/photo.jpg';
    await _client.storage
        .from(_photoBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    await _client
        .from('profiles')
        .update({'avatar_path': path})
        .eq('id', userId);
    return path;
  }

  /// A viewable link for one rider's photo, valid for [ttl].
  ///
  /// Null rather than throwing when the photo is missing or unreadable: an
  /// avatar is decoration on a screen that has a job to do, and a roster
  /// that fails to load because one rider's file went astray is worse than
  /// a roster with one initial in a circle.
  Future<String?> riderPhotoUrl(
    String? path, {
    Duration ttl = const Duration(hours: 1),
  }) async {
    if (path == null) return null;
    try {
      return await _client.storage
          .from(_photoBucket)
          .createSignedUrl(path, ttl.inSeconds);
    } catch (_) {
      return null;
    }
  }

  /// Signed links for a whole roster in one request.
  ///
  /// The Drivers screen shows every rider at once; asking for one signed
  /// URL per rider would be a request per row. Returns a map keyed by the
  /// same paths that went in, with anything unreadable simply absent.
  Future<Map<String, String>> riderPhotoUrls(
    Iterable<String> paths, {
    Duration ttl = const Duration(hours: 1),
  }) async {
    final wanted = paths.toSet().toList();
    if (wanted.isEmpty) return const {};
    try {
      final signed = await _client.storage
          .from(_photoBucket)
          .createSignedUrlsResult(wanted, ttl.inSeconds);
      // The Result variant distinguishes a missing file from a signed one;
      // the older createSignedUrls just dropped failures on the floor,
      // which would leave a rider's row looking like they never uploaded.
      return {
        for (final item in signed)
          if (item case SignedUrlSuccess(:final path, :final signedUrl))
            path: signedUrl,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<List<Profile>> fetchDrivers() async {
    final rows = await _client
        .from('profiles')
        .select()
        .eq('role', UserRole.driver.wireValue)
        .order('full_name');
    return rows.map(Profile.fromMap).toList();
  }

  /// A driver whose last fix is older than this is treated as gone - the
  /// same cutoff `Profile.hasRecentLocation` and the matching SQL in 0044
  /// already use, so "recent enough to trust" means one thing everywhere.
  static const liveLocationWindow = Duration(minutes: 15);

  /// Drivers currently sharing a position, for the Live Map. One shot -
  /// the caller polls.
  ///
  /// This used to be a realtime subscription over every driver row, which
  /// made the Live Map the most expensive screen in the product: each
  /// rider writes a position every 15 seconds, and realtime re-broadcast
  /// every one of those writes to every dispatcher watching. The cost was
  /// riders times dispatchers - it grew when you hired either.
  ///
  /// Polling the same data is flat: one query per dispatcher per tick, no
  /// matter how many riders are out. It also filters server-side, so a
  /// roster of five thousand riders returns only the hundred actually
  /// online rather than all of them for the client to sift.
  ///
  /// Nothing is lost visually. Positions were only ever redrawn as they
  /// arrived every 15 seconds; now they are fetched on the same beat.
  Future<List<Profile>> fetchLiveDriverLocations() async {
    final cutoff = DateTime.now().toUtc().subtract(liveLocationWindow);
    final rows = await _client
        .from('profiles')
        .select()
        .eq('role', UserRole.driver.wireValue)
        .eq('is_online', true)
        .gt('location_updated_at', cutoff.toIso8601String())
        .order('full_name');
    return rows.map(Profile.fromMap).toList();
  }

  /// Called by a driver's own app whenever they have moved ~25m, and
  /// every 5 minutes regardless so a waiting rider stays visible and
  /// assignable - see DriverDashboardScreen. A rider on the move
  /// therefore still reports about every 15s; a rider parked writes
  /// twelve times an hour rather than 240.
  /// Keeps flowing while the app is backgrounded/the phone is locked if
  /// the driver granted "Allow all the time"; with just "while in use" it
  /// pauses once the app leaves the foreground. Either way, the position
  /// just goes stale (and drops off the Live Map) once updates stop.
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

  /// Sets [userId]'s permission override for [permission] to [allowed] -
  /// or, with [allowed] null, clears the override so that permission falls
  /// back to their role's normal default. Only takes effect server-side if
  /// the caller is a super admin - enforced by
  /// `enforce_permission_overrides_change()`, not just this client. Reads
  /// the row back first since this is a read-modify-write on a single
  /// jsonb column, not a column that can be patched independently.
  Future<void> setPermissionOverride({
    required String userId,
    required StaffPermission permission,
    required bool? allowed,
  }) async {
    final row = await _client
        .from('profiles')
        .select('permission_overrides')
        .eq('id', userId)
        .single();
    final overrides = Map<String, dynamic>.from(
      row['permission_overrides'] as Map<String, dynamic>? ?? {},
    );
    if (allowed == null) {
      overrides.remove(permission.wireValue);
    } else {
      overrides[permission.wireValue] = allowed;
    }
    await _client
        .from('profiles')
        .update({'permission_overrides': overrides})
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

  /// Super-admin only - enforced server-side by `enforce_profile_role_change()`
  /// (same protection as `role`), not just this client. Blocks a driver
  /// from accepting a new delivery (or being assigned one) without signing
  /// them out or touching anything already in progress - e.g. for unpaid
  /// commission.
  Future<void> setFrozen(String userId, bool isFrozen) async {
    await _client
        .from('profiles')
        .update({'is_frozen': isFrozen})
        .eq('id', userId);
  }

  /// Super-admin only - enforced server-side by `enforce_profile_role_change()`
  /// (same protection as `role`/`is_frozen`), not just this client. Pins
  /// this driver to [tierId]'s daily-fee tier regardless of how many
  /// deliveries they complete - null clears the pin, back to the normal
  /// automatic tier-by-delivery-count behavior. See
  /// `daily_fee_tier_override_id` in `0038_daily_fee_tier_overrides.sql`.
  Future<void> setDailyFeeTierOverride(String userId, String? tierId) async {
    await _client
        .from('profiles')
        .update({'daily_fee_tier_override_id': tierId})
        .eq('id', userId);
  }

  /// Grants (or, with [until] null, revokes) a temporary bypass of
  /// [userId]'s daily-fee/commission access block - an emergency escape
  /// hatch for a payment-gateway outage, not a way to forgive what they
  /// owe (that's [DriverDailyFeeRepository.waiveToday] or marking a
  /// commission row waived). See `payment_access_override_until` in
  /// `0068_driver_payment_access_override.sql`.
  Future<void> setPaymentAccessOverride(String userId, DateTime? until) async {
    await _client
        .from('profiles')
        .update({'payment_access_override_until': until?.toIso8601String()})
        .eq('id', userId);
  }

  /// A driver's own "available for new deliveries" toggle, shown on their
  /// dashboard. Purely informational for dispatch/auto-assignment - not an
  /// access control (unlike [setFrozen]), so a driver may set it on
  /// themselves freely.
  Future<void> setOnline(String userId, bool isOnline) async {
    await _client
        .from('profiles')
        .update({'is_online': isOnline})
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
    DriverVehicleType? vehicleType,
    DateTime? dateOfBirth,
    String? residentialAddress,
    String? zoneId,
    String? drivingLicenseNumber,
    DateTime? drivingLicenseExpiry,
    String? vehicleInsuranceNumber,
    DateTime? vehicleInsuranceExpiry,
  }) async {
    await _client
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone': phone,
          'ghana_card_number': ghanaCardNumber,
          'vehicle_number': vehicleNumber,
          'vehicle_type': vehicleType?.wireValue,
          'date_of_birth': _dateOnly(dateOfBirth),
          'residential_address': residentialAddress,
          'zone_id': zoneId,
          'driving_license_number': drivingLicenseNumber,
          'driving_license_expiry': _dateOnly(drivingLicenseExpiry),
          'vehicle_insurance_number': vehicleInsuranceNumber,
          'vehicle_insurance_expiry': _dateOnly(vehicleInsuranceExpiry),
        })
        .eq('id', userId);
  }

  /// Creates a driver's login and profile via the "admin-create-driver"
  /// Edge Function. Callable by a dispatcher or super admin.
  Future<({String? userId, String tempPassword, bool emailSent})> createDriver({
    required String email,
    required String fullName,
    String? phone,
    String? ghanaCardNumber,
    String? vehicleNumber,
    DriverVehicleType? vehicleType,
    String? residentialAddress,
    DateTime? dateOfBirth,
    String? drivingLicenseNumber,
    DateTime? drivingLicenseExpiry,
    String? vehicleInsuranceNumber,
    DateTime? vehicleInsuranceExpiry,
  }) => _createStaffAccount(
    role: UserRole.driver,
    email: email,
    fullName: fullName,
    phone: phone,
    ghanaCardNumber: ghanaCardNumber,
    vehicleNumber: vehicleNumber,
    vehicleType: vehicleType,
    residentialAddress: residentialAddress,
    dateOfBirth: dateOfBirth,
    drivingLicenseNumber: drivingLicenseNumber,
    drivingLicenseExpiry: drivingLicenseExpiry,
    vehicleInsuranceNumber: vehicleInsuranceNumber,
    vehicleInsuranceExpiry: vehicleInsuranceExpiry,
  );

  /// Creates a dispatcher's login and profile via the same Edge Function.
  /// Only a super admin may call this - enforced server-side too.
  Future<({String? userId, String tempPassword, bool emailSent})> createDispatcher({
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

  /// Creates an auditor's login and profile via the same Edge Function.
  /// Only a super admin may call this - enforced server-side too.
  Future<({String? userId, String tempPassword, bool emailSent})> createAuditor({
    required String email,
    required String fullName,
    required String phone,
    required DateTime dateOfBirth,
    required String residentialAddress,
  }) => _createStaffAccount(
    role: UserRole.auditor,
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
  Future<({String? userId, String tempPassword, bool emailSent})> _createStaffAccount({
    required UserRole role,
    required String email,
    required String fullName,
    String? phone,
    String? ghanaCardNumber,
    String? vehicleNumber,
    DriverVehicleType? vehicleType,
    DateTime? dateOfBirth,
    String? residentialAddress,
    String? drivingLicenseNumber,
    DateTime? drivingLicenseExpiry,
    String? vehicleInsuranceNumber,
    DateTime? vehicleInsuranceExpiry,
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
          'vehicleType': vehicleType?.wireValue,
          'dateOfBirth': _dateOnly(dateOfBirth),
          'residentialAddress': residentialAddress,
          'drivingLicenseNumber': drivingLicenseNumber,
          'drivingLicenseExpiry': _dateOnly(drivingLicenseExpiry),
          'vehicleInsuranceNumber': vehicleInsuranceNumber,
          'vehicleInsuranceExpiry': _dateOnly(vehicleInsuranceExpiry),
          'role': role.wireValue,
        },
      );
      final data = response.data as Map<String, dynamic>;
      return (
        // Nullable on purpose: the Edge Function returns the new auth
        // user's id, but this is the only caller that needs it and it
        // only costs an optional photo upload if it ever goes missing -
        // never the account itself.
        userId: data['userId'] as String?,
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

  /// Resets a driver's/dispatcher's/auditor's password to a new random
  /// temporary one via the "admin-reset-password" Edge Function - for when
  /// someone's forgotten theirs and "Forgot password?" isn't an option.
  /// Only a super admin may call this - enforced server-side too, same
  /// footing as [updateEmail]. They're emailed the new password directly
  /// and must set their own on next sign-in; [tempPassword] is still
  /// returned as a fallback to share by hand if [emailSent] is false.
  Future<({String tempPassword, bool emailSent})> resetPassword(
    String userId,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'admin-reset-password',
        body: {'userId': userId},
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

  /// Sends a driver a free-form message via just one channel - [channel]
  /// must be `'sms'` or `'email'` - via the "admin-message-driver" Edge
  /// Function. Dispatcher-or-above only, enforced server-side.
  Future<void> messageDriver({
    required String driverId,
    required String channel,
    required String message,
  }) async {
    try {
      await _client.functions.invoke(
        'admin-message-driver',
        body: {'driverId': driverId, 'channel': channel, 'message': message},
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
