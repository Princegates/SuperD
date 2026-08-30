import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/driver_vehicle_type.dart';
import '../../shared/utils/audit_log.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  /// Logged here, once, rather than at each of the login screen/driver
  /// signup screen's call sites - this is the one place every sign-in
  /// actually happens, so it can't be missed by a future call site the way
  /// scattered per-screen logging calls could be. [changePassword] below
  /// re-verifies a password the same way but calls the SDK directly rather
  /// than this method, so it deliberately doesn't also log a "signed in".
  Future<void> signIn({required String email, required String password}) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    await logAuditEvent(
      _client,
      action: 'user_signed_in',
      entityType: 'auth',
      entityId: response.user?.id,
      summary: 'Signed in',
    );
  }

  /// Self-service driver signup - the native app only (the web dashboard
  /// keeps this route out of reach entirely, see the router). Every account
  /// created this way lands with role `driver`: `handle_new_user()`, the
  /// trigger that creates the profile row, never reads a role from the
  /// signup payload, so there's no way to escalate into dispatcher or
  /// super_admin through this path.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String? vehicleNumber,
    DriverVehicleType? vehicleType,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'phone': phone,
        'vehicle_number': vehicleNumber,
        'vehicle_type': vehicleType?.wireValue,
      },
    );
    // Only if signup actually established a session - with email
    // confirmation required, there's no session (and so no JWT to call
    // this RPC as) until the driver clicks the link, at which point they
    // go through signIn() like anyone else and that gets logged instead.
    if (response.session != null) {
      await logAuditEvent(
        _client,
        action: 'user_signed_up',
        entityType: 'auth',
        entityId: response.user?.id,
        summary: 'Signed up as a driver ($fullName)',
      );
    }
    return response;
  }

  /// Logs the sign-out *before* actually signing out - `log_audit_event`
  /// needs a live session's `auth.uid()` to attribute the entry, which
  /// signing out first would erase.
  Future<void> signOut() async {
    await logAuditEvent(
      _client,
      action: 'user_signed_out',
      entityType: 'auth',
      entityId: currentUser?.id,
      summary: 'Signed out',
    );
    await _client.auth.signOut();
  }

  /// Sends a password-recovery email containing a one-time code. The
  /// Supabase project's "Reset Password" email template must include
  /// `{{ .Token }}` for the code to appear (see README).
  Future<void> sendPasswordResetCode(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  /// Verifies the code from the recovery email, establishing a session,
  /// then sets [newPassword] on the account.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.recovery,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Changes the signed-in user's password, re-verifying [currentPassword]
  /// first so a device left unlocked can't have its password swapped out
  /// by anyone who picks it up.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final email = currentUser?.email;
    if (email == null) {
      throw StateError('No signed-in user to change the password for.');
    }
    await _client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
