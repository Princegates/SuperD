import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/driver_vehicle_type.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  User? get currentUser => _client.auth.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
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
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'phone': phone,
        'vehicle_number': vehicleNumber,
        'vehicle_type': vehicleType?.wireValue,
      },
    );
  }

  Future<void> signOut() => _client.auth.signOut();

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
