import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/profile.dart';
import '../../../shared/widgets/account_menu_button.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/delivery_card.dart';
import '../../../shared/widgets/staggered_list_item.dart';
import '../providers/driver_providers.dart';
import '../widgets/daily_fee_banner.dart';
import '../widgets/driver_notice_banner.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() =>
      _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends ConsumerState<DriverDashboardScreen> {
  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _startSharingLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// Shares this driver's position with dispatch for as long as this
  /// screen stays mounted (i.e. they're signed in as a driver) and
  /// location is granted - including while the app is backgrounded or the
  /// phone is locked, as long as they've granted "Allow all the time" (see
  /// `_requestBackgroundPermissionIfPossible`). With only "while in use"
  /// granted, updates still work but pause once the app leaves the
  /// foreground - same as before this used a stream. Either way, nothing
  /// persists once the app is fully closed, and a transient GPS/network
  /// failure on one update is silently skipped, not fatal.
  Future<void> _startSharingLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint(
        'SuperD: location services are off on this device - live '
        'location sharing needs them enabled.',
      );
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('SuperD: location permission not granted ($permission).');
      return;
    }

    if (permission == LocationPermission.whileInUse) {
      permission = await _requestBackgroundPermissionIfPossible();
    }

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: _locationSettingsFor(
            backgroundAllowed: permission == LocationPermission.always,
          ),
        ).listen(
          _pushLocation,
          onError: (Object e) =>
              debugPrint('SuperD: live location stream error: $e'),
        );
  }

  /// Asks for "Allow all the time" on top of the "while in use" grant
  /// they've already given - needed for location updates to keep flowing
  /// once the app is backgrounded/the phone is locked. On Android 11+ and
  /// most iOS versions the OS won't show a second permission dialog for
  /// this (a platform restriction, not something this app controls) - the
  /// driver has to flip it on from system Settings instead, so this points
  /// them there rather than silently giving up. Foreground-only tracking
  /// (the previous behaviour) still works fine either way.
  Future<LocationPermission> _requestBackgroundPermissionIfPossible() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.always || !mounted) {
      return permission;
    }

    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep sharing location in the background?'),
        content: const Text(
          'Right now dispatch and customers only see your position while '
          'SuperD is open on screen. To keep sharing it while the app is '
          'in the background or your phone is locked, allow location '
          'access "All the time" in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (openSettings ?? false) {
      await Geolocator.openAppSettings();
    }
    return permission;
  }

  /// Platform-specific tuning for the live position stream. On Android,
  /// [backgroundAllowed] runs a foreground service (with the required
  /// persistent notification) so updates keep flowing once the app is
  /// backgrounded; on iOS, it enables the equivalent background delivery -
  /// both no-ops if the driver only granted "while in use", which is fine,
  /// updates just pause in the background same as before. See
  /// `AndroidManifest.xml`/`Info.plist` for the permissions this depends on.
  LocationSettings _locationSettingsFor({required bool backgroundAllowed}) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: backgroundAllowed
            ? const ForegroundNotificationConfig(
                notificationTitle: 'SuperD',
                notificationText: 'Sharing your location with dispatch',
                enableWakeLock: true,
              )
            : null,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.otherNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: backgroundAllowed,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );
  }

  Future<void> _pushLocation(Position position) async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateLiveLocation(
            userId: userId,
            lat: position.latitude,
            lng: position.longitude,
          );
    } catch (e) {
      // Best-effort - skip this update, the next one from the stream will
      // try again. Logged (not shown to the driver) so a persistent
      // failure is visible in `flutter run` output instead of silently
      // never updating.
      debugPrint('SuperD: live location update failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = ref.watch(myDeliveriesProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final totalCommissionDue = ref.watch(totalCommissionDueProvider);
    final commissionDueAmount = ref.watch(commissionDueAmountProvider);
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    final currency = appSettings?.currency;
    final latestAttempt = ref.watch(dailyFeeLatestAttemptProvider);
    final freeDayBalance = ref.watch(freeDayBalanceProvider).valueOrNull ?? 0;
    final dailyFeeOn =
        (appSettings?.driverCommissionEnabled ?? true) &&
        (ref.watch(dailyFeeTiersProvider).valueOrNull?.isNotEmpty ?? false);
    final notices = ref.watch(myVisibleNoticesProvider).valueOrNull ?? [];
    final todaysRevenue = ref.watch(todaysRevenueProvider);

    // A driver's own delivery list re-emits the full set on every change -
    // only ids that weren't there last time are a genuinely new assignment.
    // previous == null (still loading) is skipped so the very first load
    // doesn't fire one notification per existing delivery.
    ref.listen<AsyncValue<List<Delivery>>>(myDeliveriesProvider, (
      previous,
      next,
    ) {
      final priorIds = previous?.valueOrNull?.map((d) => d.id).toSet();
      final current = next.valueOrNull;
      if (priorIds == null || current == null) return;
      for (final delivery in current) {
        if (!priorIds.contains(delivery.id)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('New delivery assigned: #${delivery.trackingCode}'),
              action: SnackBarAction(
                label: 'View',
                onPressed: () =>
                    context.push('/driver/delivery/${delivery.id}'),
              ),
            ),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile != null ? 'Hi, ${profile.displayName}' : 'My deliveries',
        ),
        actions: [
          IconButton(
            tooltip: 'My route',
            icon: const Icon(Icons.alt_route_outlined),
            onPressed: () => context.push('/driver/route'),
          ),
          IconButton(
            tooltip: 'My rides',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push('/driver/rides'),
          ),
          const AccountMenuButton(
            changePasswordRoute: '/driver/change-password',
          ),
        ],
      ),
      body: Column(
        children: [
          if (profile != null) _AvailabilityBar(profile: profile),
          _RevenueStrip(amount: todaysRevenue, currency: currency ?? 'GHS'),
          if (profile?.isFrozen ?? false) const _FrozenBanner(),
          if (notices.isNotEmpty) ...[
            const SizedBox(height: 10),
            DriverNoticeList(notices: notices),
          ],
          if (totalCommissionDue > 0)
            DailyFeeBanner(
              feeAmount: totalCommissionDue,
              commissionDueAmount: commissionDueAmount,
              currency: currency ?? 'GHS',
              status: latestAttempt?.status,
              driverPhone: profile?.phone,
            ),
          if (dailyFeeOn && freeDayBalance > 0)
            _FreeDayBalanceStrip(balance: freeDayBalance),
          Expanded(child: _DeliveryList(deliveries: deliveries)),
        ],
      ),
    );
  }
}

/// A driver's own "available for new deliveries" toggle - purely
/// informational for dispatch/auto-assignment, not an access control (see
/// `is_online` in `0025_driver_categories_and_status.sql`).
class _AvailabilityBar extends ConsumerWidget {
  const _AvailabilityBar({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: profile.isOnline
          ? AppTheme.success.withValues(alpha: 0.08)
          : Colors.grey.shade100,
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 10,
            color: profile.isOnline ? AppTheme.success : Colors.grey.shade400,
          ),
          const SizedBox(width: 8),
          Text(
            profile.isOnline
                ? 'Online - available for deliveries'
                : 'Offline - not receiving new deliveries',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const Spacer(),
          Switch(
            value: profile.isOnline,
            onChanged: (value) => ref
                .read(profileRepositoryProvider)
                .setOnline(profile.id, value),
          ),
        ],
      ),
    );
  }
}

/// A live running total of what this driver has collected today - see
/// [todaysRevenueProvider]. Always shown (even at zero, so it's obvious
/// this is a live counter and not just missing) and tappable straight
/// into [EarningsScreen] for the daily/weekly/monthly/yearly breakdown
/// and commission payment history.
class _RevenueStrip extends StatelessWidget {
  const _RevenueStrip({required this.amount, required this.currency});

  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/driver/earnings'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: AppTheme.primary.withValues(alpha: 0.05),
        child: Row(
          children: [
            // Not const: AppTheme.primary is theme-selectable, unlike the
            // fixed status colors (success/warning/danger/neutral).
            Icon(Icons.payments_outlined, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              "Today's revenue: $currency ${amount.toStringAsFixed(2)}",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: AppTheme.primary,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}

class _FrozenBanner extends StatelessWidget {
  const _FrozenBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.danger.withValues(alpha: 0.1),
      child: const Row(
        children: [
          Icon(Icons.ac_unit, size: 18, color: AppTheme.danger),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your account is frozen - you can finish deliveries already '
              "assigned to you, but can't accept a new one. Contact "
              'dispatch to resolve this.',
              style: TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A driver's incentive-earned free commission days, not yet spent - see
/// `driver_free_day_credits` in `0032_commission_free_days.sql`. Shown
/// even when today's own fee has already been covered (by a credit or a
/// real payment), so a driver who's built up a balance for later can see
/// it - a reward should be visible, not just quietly applied.
class _FreeDayBalanceStrip extends StatelessWidget {
  const _FreeDayBalanceStrip({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.success.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(
            Icons.card_giftcard_outlined,
            size: 16,
            color: AppTheme.success,
          ),
          const SizedBox(width: 8),
          Text(
            'You have $balance free commission day${balance == 1 ? '' : 's'} '
            'banked',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              color: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryList extends ConsumerWidget {
  const _DeliveryList({required this.deliveries});

  final AsyncValue<List<Delivery>> deliveries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<Delivery>>(
      value: deliveries,
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No deliveries assigned to you yet.',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        final active = items
            .where(
              (d) =>
                  d.status != DeliveryStatus.delivered &&
                  d.status != DeliveryStatus.cancelled,
            )
            .toList();
        final finished = items
            .where(
              (d) =>
                  d.status == DeliveryStatus.delivered ||
                  d.status == DeliveryStatus.cancelled,
            )
            .toList();

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myDeliveriesProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (active.isNotEmpty) ...[
                _SectionHeader('Active (${active.length})'),
                for (final (index, delivery) in active.indexed) ...[
                  StaggeredListItem(
                    index: index,
                    child: DeliveryCard(
                      delivery: delivery,
                      onTap: () =>
                          context.push('/driver/delivery/${delivery.id}'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (finished.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SectionHeader('Completed'),
                for (final (index, delivery) in finished.indexed) ...[
                  StaggeredListItem(
                    index: active.length + index,
                    child: DeliveryCard(
                      delivery: delivery,
                      onTap: () =>
                          context.push('/driver/delivery/${delivery.id}'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
          color: Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
