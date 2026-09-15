import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/data/repositories/vendor_repository.dart';
import 'package:superd/shared/widgets/live_eta.dart';

/// Every ETA recompute is a billed Directions call that can never be
/// served from the route cache - the origin is the rider, so it has moved
/// by definition. The displayed figure used to sit frozen between calls,
/// which is part of what forced them to be frequent.
///
/// These pin the bargain that replaced that: the number counts down on its
/// own, so it reads as live between calls, and it refuses to count all the
/// way to zero - announcing an arrival the app has no evidence for would
/// be worse than saying nothing.
class _StubVendorRepository implements VendorRepository {
  _StubVendorRepository(this.minutes);

  final int minutes;
  int calls = 0;

  @override
  Future<RoadRoute?> fetchRoadRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    calls++;
    return RoadRoute(distanceKm: 6.0, durationMinutes: minutes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'LiveEta must not reach past fetchRoadRoute: ${invocation.memberName}',
  );
}

Widget _host(_StubVendorRepository repo, {required DateTime positionAt}) {
  return ProviderScope(
    overrides: [vendorRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Scaffold(
        body: LiveEta(
          originLat: 5.556,
          originLng: -0.205,
          destLat: 5.603,
          destLng: -0.187,
          positionUpdatedAt: positionAt,
          label: 'Drop-off in about',
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('it shows the fetched ETA once the route comes back', (t) async {
    final repo = _StubVendorRepository(18);
    await t.pumpWidget(_host(repo, positionAt: DateTime.now()));
    await t.pump();
    await t.pump();

    expect(find.textContaining('18 min'), findsOneWidget);
    expect(repo.calls, 1);
  });

  testWidgets('one call, not one per tick', (t) async {
    final repo = _StubVendorRepository(18);
    await t.pumpWidget(_host(repo, positionAt: DateTime.now()));
    await t.pump();
    await t.pump();

    // Several stale-ticker periods with the rider not moving. The old
    // 30-second floor plus a frozen display meant this window was where
    // the calls piled up.
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 30));
    }
    expect(
      repo.calls,
      1,
      reason: 'a stationary rider bought the same route more than once',
    );
  });

  testWidgets('it never counts down to an arrival it cannot vouch for', (
    t,
  ) async {
    // A route shorter than the floor: there is no honest figure to show
    // from the start, so nothing is shown rather than "arriving now".
    final repo = _StubVendorRepository(1);
    await t.pumpWidget(_host(repo, positionAt: DateTime.now()));
    await t.pump();
    await t.pump();

    expect(find.textContaining('min'), findsNothing);
  });
}
