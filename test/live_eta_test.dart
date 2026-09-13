import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/data/repositories/vendor_repository.dart';
import 'package:superd/shared/widgets/live_eta.dart';

/// An ETA is a promise to someone standing at a gate. These pin down the
/// three cases where the honest answer is to say nothing at all, because
/// a confident wrong number is worse than no number.

/// Implements rather than extends, so no real SupabaseClient is built -
/// constructing one starts GoTrue's auto-refresh timer, which outlives
/// the test and fails it on a pending timer. noSuchMethod covers the rest
/// of the interface, none of which this widget touches.
class _StubVendorRepository implements VendorRepository {
  _StubVendorRepository(this.route);

  /// What Directions is pretending to answer. Null stands in for the
  /// function not being deployed, no route, or a refused key.
  final RoadRoute? route;

  int calls = 0;

  @override
  Future<RoadRoute?> fetchRoadRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    calls++;
    return route;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Widget _host({
  required _StubVendorRepository repo,
  required DateTime? positionUpdatedAt,
}) {
  return ProviderScope(
    overrides: [vendorRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      home: Scaffold(
        body: LiveEta(
          // Osu to East Legon, roughly.
          originLat: 5.5560,
          originLng: -0.1820,
          destLat: 5.6350,
          destLng: -0.1580,
          positionUpdatedAt: positionUpdatedAt,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the time when the rider was heard from just now', (
    tester,
  ) async {
    final repo = _StubVendorRepository(
      const RoadRoute(distanceKm: 6.4, durationMinutes: 18),
    );
    await tester.pumpWidget(
      _host(repo: repo, positionUpdatedAt: DateTime.now()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('18 min'), findsOneWidget);
  });

  testWidgets('says nothing when the position is stale', (tester) async {
    final repo = _StubVendorRepository(
      const RoadRoute(distanceKm: 6.4, durationMinutes: 18),
    );
    await tester.pumpWidget(
      _host(
        repo: repo,
        // A rider whose phone stopped reporting half an hour ago. An ETA
        // from that is fiction, however confident it looks.
        positionUpdatedAt: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('min'), findsNothing);
    // And it must not have spent a Directions call working that out.
    expect(repo.calls, 0);
  });

  testWidgets('says nothing when Directions cannot answer', (tester) async {
    // The state the system is actually in until get-road-distance is
    // deployed: every call comes back empty.
    final repo = _StubVendorRepository(null);
    await tester.pumpWidget(
      _host(repo: repo, positionUpdatedAt: DateTime.now()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('min'), findsNothing);
    expect(find.byType(LiveEta), findsOneWidget);
  });

  testWidgets('a route with distance but no time is still not an ETA', (
    tester,
  ) async {
    final repo = _StubVendorRepository(
      const RoadRoute(distanceKm: 6.4, durationMinutes: null),
    );
    await tester.pumpWidget(
      _host(repo: repo, positionUpdatedAt: DateTime.now()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('min'), findsNothing);
  });

  testWidgets('reads an hour or more as hours, not as ninety-five minutes', (
    tester,
  ) async {
    final repo = _StubVendorRepository(
      const RoadRoute(distanceKm: 48, durationMinutes: 95),
    );
    await tester.pumpWidget(
      _host(repo: repo, positionUpdatedAt: DateTime.now()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1h 35min'), findsOneWidget);
  });
}
