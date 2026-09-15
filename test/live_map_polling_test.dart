import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/data/repositories/profile_repository.dart';
import 'package:superd/features/admin/providers/admin_providers.dart';
import 'package:superd/models/profile.dart';
import 'package:superd/models/user_role.dart';

/// The Live Map used to hold a realtime subscription over every driver
/// row, for the life of the session, whether or not anyone had the map on
/// screen. Riders push a position every 15 seconds, so that cost was
/// riders times dispatchers - and it was paid even by a dispatcher who
/// had opened the map once that morning.
///
/// Polling only helps if it actually stops. These tests pin the two
/// properties that make the change worth anything: it keeps asking while
/// someone is looking, and it stops the moment nobody is.
class _CountingProfileRepository implements ProfileRepository {
  _CountingProfileRepository();

  int calls = 0;

  @override
  Future<List<Profile>> fetchLiveDriverLocations() async {
    calls++;
    return [
      Profile(
        id: 'driver-1',
        email: 'kofi@example.com',
        fullName: 'Kofi Mensah',
        role: UserRole.driver,
        isActive: true,
        lastLat: 5.556,
        lastLng: -0.205,
        locationUpdatedAt: DateTime.now(),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
        'The Live Map must not reach past fetchLiveDriverLocations: '
        '${invocation.memberName}',
      );
}

void main() {
  late _CountingProfileRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _CountingProfileRepository();
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        // Real seconds are not the thing under test - the loop's shape is.
        liveMapPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('the map asks as soon as it is watched', () async {
    final sub = container.listen(driverLocationsProvider, (_, _) {});
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      repo.calls,
      greaterThanOrEqualTo(1),
      reason: 'the map showed nothing until the first interval elapsed',
    );
  });

  test('it keeps asking while someone is watching', () async {
    final sub = container.listen(driverLocationsProvider, (_, _) {});
    addTearDown(sub.close);

    // Several poll intervals. If the loop ran only once, the map would
    // silently freeze on the first fix every rider sent.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(repo.calls, greaterThanOrEqualTo(3));
  });

  test('it stops the moment the last viewer leaves', () async {
    final sub = container.listen(driverLocationsProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(repo.calls, greaterThanOrEqualTo(1));

    sub.close();
    // One in-flight poll may still land, so take the count just after
    // closing rather than assuming a number: the property under test is
    // that it stops growing, not what it stopped at.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final atClose = repo.calls;

    // Many intervals later. This is the whole point of the change, and
    // the assertion that fails if autoDispose is ever dropped.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      repo.calls,
      atClose,
      reason: 'the map kept polling after the last viewer left',
    );
  });
}
