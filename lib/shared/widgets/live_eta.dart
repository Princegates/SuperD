import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/providers/core_providers.dart';
import '../../core/theme/app_theme.dart';

/// "Arriving in about 12 min", worked out from where the rider actually
/// is right now.
///
/// Shared by the customer's tracking page and the rider's own screen,
/// because it is the same question from two sides - the person waiting
/// wants to know when to come to the gate, and the rider wants to know
/// what to tell them.
///
/// Three things keep this honest rather than merely plausible:
///
///  * It is silent unless the rider's position is recent. A phone that
///    stopped reporting twenty minutes ago can still produce a confident
///    number, and that number is a lie. [positionUpdatedAt] older than
///    [_staleAfter] renders nothing at all.
///  * It is silent when Directions cannot answer - no route, no key, the
///    function not deployed. An ETA is a nice-to-have and must never
///    turn into an error message on a page someone is anxiously
///    watching.
///  * It refuses to ask Google more often than the answer can change:
///    only once the rider has actually moved [_recomputeAfterMetres], or
///    [_recomputeAfterIdle] has passed, and never twice inside
///    [_minimumGap]. The page it sits on polls every five seconds; this
///    does not.
class LiveEta extends ConsumerStatefulWidget {
  const LiveEta({
    super.key,
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.positionUpdatedAt,
    this.label = 'Arriving in about',
    this.compact = false,
  });

  /// Where the rider is now. Comes from the same poll that drives the
  /// rest of the page, so it changes as they move.
  final double originLat;
  final double originLng;

  final double destLat;
  final double destLng;

  /// When the rider's position was last reported. Null is treated as
  /// unknown, and therefore not shown.
  final DateTime? positionUpdatedAt;

  final String label;

  /// Smaller treatment for sitting inside an existing dense row.
  final bool compact;

  @override
  ConsumerState<LiveEta> createState() => _LiveEtaState();
}

class _LiveEtaState extends ConsumerState<LiveEta> {
  static const _staleAfter = Duration(minutes: 5);
  static const _recomputeAfterIdle = Duration(minutes: 2);
  static const _minimumGap = Duration(seconds: 30);
  static const _recomputeAfterMetres = 300.0;

  static const _distance = Distance();

  int? _minutes;
  DateTime? _computedAt;
  LatLng? _computedFrom;
  bool _inFlight = false;

  /// Ticks the "stale" check along even when no new position arrives, so
  /// a rider whose phone went quiet stops showing an ETA on its own
  /// rather than leaving the last one up indefinitely.
  Timer? _staleTicker;

  bool get _positionIsFresh {
    final at = widget.positionUpdatedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < _staleAfter;
  }

  @override
  void initState() {
    super.initState();
    _staleTicker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => mounted ? setState(() {}) : null,
    );
    unawaited(_refreshIfWorthwhile());
  }

  @override
  void didUpdateWidget(LiveEta old) {
    super.didUpdateWidget(old);
    unawaited(_refreshIfWorthwhile());
  }

  @override
  void dispose() {
    _staleTicker?.cancel();
    super.dispose();
  }

  bool _shouldRecompute() {
    if (_inFlight || !_positionIsFresh) return false;
    if (_computedAt == null || _computedFrom == null) return true;

    final since = DateTime.now().difference(_computedAt!);
    if (since < _minimumGap) return false;
    if (since > _recomputeAfterIdle) return true;

    final moved = _distance.as(
      LengthUnit.Meter,
      _computedFrom!,
      LatLng(widget.originLat, widget.originLng),
    );
    return moved >= _recomputeAfterMetres;
  }

  Future<void> _refreshIfWorthwhile() async {
    if (!_shouldRecompute()) return;
    final from = LatLng(widget.originLat, widget.originLng);
    _inFlight = true;
    try {
      final route = await ref
          .read(vendorRepositoryProvider)
          .fetchRoadRoute(
            originLat: from.latitude,
            originLng: from.longitude,
            destLat: widget.destLat,
            destLng: widget.destLng,
          );
      if (!mounted) return;
      setState(() {
        // A null duration leaves whatever was last known in place rather
        // than blanking a figure someone is watching over one bad call.
        if (route?.durationMinutes case final minutes?) {
          _minutes = minutes;
          _computedAt = DateTime.now();
          _computedFrom = from;
        }
      });
    } finally {
      _inFlight = false;
    }
  }

  static String _spoken(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return hours == 1 ? '1 hour' : '$hours hours';
    return '${hours}h ${rest}min';
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _minutes;
    // Nothing to say, or no longer entitled to say it.
    if (minutes == null || !_positionIsFresh) return const SizedBox.shrink();

    final text = '${widget.label} ${_spoken(minutes)}';
    if (widget.compact) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.primary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 15,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
