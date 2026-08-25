import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';
import '../../models/user_role.dart';

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
}
