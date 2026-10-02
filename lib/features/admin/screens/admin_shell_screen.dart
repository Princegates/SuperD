import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/console_design.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/user_role.dart';
import '../../../models/vendor.dart';
import '../../../shared/widgets/account_menu_button.dart';
import '../../../shared/widgets/connection_status_dot.dart';
import '../../console/screens/console_audit_log_tab.dart';
import '../../console/screens/console_commission_tab.dart';
import '../../console/screens/console_customers_tab.dart';
import '../../console/screens/console_daily_fees_tab.dart';
import '../../console/screens/console_dashboard_tab.dart';
import '../../console/screens/console_finance_tab.dart';
import '../../console/screens/console_notices_tab.dart';
import '../../console/screens/console_reports_tab.dart';
import '../../console/screens/console_onboarding_tab.dart';
import '../../console/screens/console_settings_tab.dart';
import '../../console/screens/console_system_health_tab.dart';
import '../../console/screens/console_zones_tab.dart';
import '../providers/admin_providers.dart';
import 'admin_dashboard_screen.dart';
import 'drivers_screen.dart';
import 'home_screen.dart';
import 'live_map_screen.dart';
import 'team_screen.dart';
import 'vendors_screen.dart';

class _AdminSection {
  const _AdminSection(
    this.icon,
    this.label,
    this.body, {
    this.superAdminOnly = false,
    this.superAdminExclusive = false,
  });

  final IconData icon;
  final String label;
  final Widget body;

  /// Team/reporting/finance/audit/onboarding/zones/settings are hidden
  /// from a plain dispatcher's nav entirely, on top of the RLS that
  /// already keeps most of their underlying writes out of reach either
  /// way. Shown to a super admin AND an auditor (see
  /// [UserRole.canViewAdminConsole]) - an auditor sees exactly the same
  /// sections a super admin does, just without the ability to write to
  /// the admin-level ones (Team, Zones, Settings) once inside - see
  /// `0054_auditor_role_permissions.sql`.
  final bool superAdminOnly;

  /// Off-limits even to an auditor - unlike every other superAdminOnly
  /// section. Customers is the one case so far: customer contact details
  /// (name/email/phone/address) aren't something an oversight role needs
  /// to see - see `0055_customer_directory.sql`. Meaningless unless
  /// [superAdminOnly] is also true.
  final bool superAdminExclusive;

  bool visibleTo(UserRole? role) {
    if (!superAdminOnly) return true;
    if (superAdminExclusive) return role == UserRole.superAdmin;
    return role?.canViewAdminConsole ?? false;
  }
}

/// The whole back-office experience in one place: every section a
/// dispatcher, auditor, or super admin can reach, behind a single
/// persistent navigation surface instead of separate full-screen pages you
/// push into and back out of. What shows up in the nav is role-based - a
/// dispatcher sees Deliveries/Drivers/Vendors/Commission/Daily
/// Fees/Notices (confirming what a driver owes/has paid, managing the
/// driver roster itself, and posting a promotion/message to drivers, are
/// all routine dispatch work, not a super-admin-only decision - matching
/// the RLS on `commission_payments`/`driver_daily_fees`/`driver_notices`,
/// which already allow either role); a super admin AND an auditor also see
/// Team and the remaining Console sections (Reports, Finance, Audit log,
/// Onboarding, Zones, Settings) - an auditor can view every one of these
/// but can't write to the admin-level ones (dispatcher/super-admin
/// management is exclusive to a super admin, so is the rest of Team; an
/// auditor's own read-only access is enforced server-side, not just by
/// hiding buttons - see `0054_auditor_role_permissions.sql`). Customers and
/// System Health are the two sections a super admin does NOT share with an
/// auditor at all (see [_AdminSection.superAdminExclusive]) - customer
/// contact details and infra/integration status aren't things an oversight
/// role needs, unlike everything else here.
///
/// Slot 0 itself is role-conditional rather than a fixed section: a
/// dispatcher gets a lightweight quick-link Home; a super admin/auditor
/// gets the richer [ConsoleDashboardTab] (trends, a unified alerts feed,
/// recent activity) in that same slot instead - see `build()`.
///
/// See [DriversScreen] for why the driver roster is split out into its
/// own section instead of living under Team.
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _index = 0;

  // _NavList relies on every non-superAdminOnly section coming first,
  // contiguously, followed by every superAdminOnly one - that's what
  // decides where its "ADMIN CONSOLE" divider lands (see opsCount there).
  // So order matters here, not just each entry's own flag.
  static const _restOfSections = [
    _AdminSection(
      Icons.local_shipping_outlined,
      'Deliveries',
      AdminDashboardScreen(),
    ),
    _AdminSection(Icons.two_wheeler_outlined, 'Drivers', DriversScreen()),
    _AdminSection(Icons.storefront_outlined, 'Vendors', VendorsScreen()),
    _AdminSection(Icons.near_me_outlined, 'Live Map', LiveMapScreen()),
    _AdminSection(
      Icons.request_quote_outlined,
      'Commission',
      ConsoleCommissionTab(),
    ),
    _AdminSection(
      Icons.calendar_today_outlined,
      'Daily Fees',
      ConsoleDailyFeesTab(),
    ),
    _AdminSection(Icons.campaign_outlined, 'Notices', ConsoleNoticesTab()),
    _AdminSection(
      Icons.badge_outlined,
      'Team',
      TeamScreen(),
      superAdminOnly: true,
    ),
    _AdminSection(
      Icons.contacts_outlined,
      'Customers',
      ConsoleCustomersTab(),
      superAdminOnly: true,
      superAdminExclusive: true,
    ),
    _AdminSection(
      Icons.summarize_outlined,
      'Reports',
      ConsoleReportsTab(),
      superAdminOnly: true,
    ),
    _AdminSection(
      Icons.payments_outlined,
      'Finance',
      ConsoleFinanceTab(),
      superAdminOnly: true,
    ),
    _AdminSection(
      Icons.receipt_long_outlined,
      'Audit log',
      ConsoleAuditLogTab(),
      superAdminOnly: true,
    ),
    // Exclusive to a super admin, same as Customers - this is infra
    // recon (what third-party secrets are set, raw rate-limit/cache
    // volume), not an oversight/audit concern an auditor's read-only
    // role exists to cover. The admin-integration-status Edge Function
    // and the two RPCs in 0099_rate_limit_and_cache_admin_stats.sql
    // enforce the same restriction server-side.
    _AdminSection(
      Icons.monitor_heart_outlined,
      'System Health',
      ConsoleSystemHealthTab(),
      superAdminOnly: true,
      superAdminExclusive: true,
    ),
    _AdminSection(
      Icons.how_to_reg_outlined,
      'Onboarding',
      ConsoleOnboardingTab(),
      superAdminOnly: true,
    ),
    _AdminSection(
      Icons.map_outlined,
      'Zones',
      ConsoleZonesTab(),
      superAdminOnly: true,
    ),
    _AdminSection(
      Icons.settings_outlined,
      'Settings',
      ConsoleSettingsTab(),
      superAdminOnly: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final myRole = ref.watch(currentProfileProvider).valueOrNull?.role;
        // Riders pay commission only now, so the daily fee is off (no
        // tiers configured). Showing the section anyway advertises a
        // charge nobody makes. Keyed off the tiers themselves rather
        // than a flag, so it comes back on its own if one is ever set.
        final dailyFeeInUse =
            ref.watch(dailyFeeTiersProvider).valueOrNull?.isNotEmpty ?? false;

        // The full delivery list re-emits on every change - diffing by id
        // tells apart a genuinely new order (never seen this id before)
        // from an existing delivery whose status just changed. previous ==
        // null (still loading) is skipped so the first load doesn't fire
        // one notification per already-existing delivery.
        ref.listen<AsyncValue<List<Delivery>>>(recentDeliveriesProvider, (
          previous,
          next,
        ) {
          final priorById = {
            for (final d in previous?.valueOrNull ?? <Delivery>[]) d.id: d,
          };
          final current = next.valueOrNull;
          if (previous?.valueOrNull == null || current == null) return;
          for (final delivery in current) {
            final prior = priorById[delivery.id];
            if (prior == null) {
              if (delivery.status == DeliveryStatus.pending) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'New delivery request from ${delivery.customerName}',
                    ),
                    action: SnackBarAction(
                      label: 'View',
                      onPressed: () =>
                          context.push('/admin/delivery/${delivery.id}'),
                    ),
                  ),
                );
              }
            } else if (prior.status == DeliveryStatus.assigned &&
                delivery.status == DeliveryStatus.pending) {
              // A driver rejected it (or it was manually unassigned) -
              // either way it needs a new driver.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Delivery #${delivery.trackingCode} is unassigned and '
                    'needs a new driver',
                  ),
                  action: SnackBarAction(
                    label: 'View',
                    onPressed: () =>
                        context.push('/admin/delivery/${delivery.id}'),
                  ),
                ),
              );
            }
          }
        });

        final restOfSections = [
          for (final section in _restOfSections)
            if (section.visibleTo(myRole) &&
                (dailyFeeInUse || section.label != 'Daily Fees'))
              section,
        ];

        void goToLabel(String label) {
          final i = restOfSections.indexWhere((s) => s.label == label);
          if (i != -1) setState(() => _index = i + 1);
        }

        // Same diffing approach as the new-delivery listener above - only
        // ids that weren't there last time are a genuinely new vendor.
        ref.listen<AsyncValue<List<Vendor>>>(vendorRegistrationsProvider, (
          previous,
          next,
        ) {
          final priorIds = previous?.valueOrNull?.map((v) => v.id).toSet();
          final current = next.valueOrNull;
          if (priorIds == null || current == null) return;
          for (final vendor in current) {
            if (!priorIds.contains(vendor.id)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('New vendor registered: ${vendor.vendorName}'),
                  action: SnackBarAction(
                    label: 'View',
                    onPressed: () => goToLabel('Vendors'),
                  ),
                ),
              );
            }
          }
        });

        // Slot 0 is role-conditional rather than always HomeScreen: a
        // super admin/auditor gets the rich Dashboard (trends, a unified
        // alerts feed, recent activity - several of its providers
        // resolve to an RLS-restricted empty list for a plain dispatcher,
        // which would read as a broken/empty screen rather than "nothing
        // to see here"), while a dispatcher keeps today's lightweight
        // quick-link Home unchanged. See `canViewAdminConsole`.
        final landing = (myRole?.canViewAdminConsole ?? false)
            ? _AdminSection(
                Icons.dashboard_outlined,
                'Dashboard',
                ConsoleDashboardTab(onNavigate: goToLabel),
              )
            : _AdminSection(
                Icons.dashboard_outlined,
                'Home',
                HomeScreen(
                  quickLinks: [
                    for (final section in restOfSections)
                      DashboardQuickLink(section.icon, section.label),
                  ],
                  onNavigate: goToLabel,
                ),
              );
        final sections = [landing, ...restOfSections];
        final index = _index.clamp(0, sections.length - 1);
        final isWide = MediaQuery.sizeOf(context).width >= 900;

        void select(int i) => setState(() => _index = i);

        return Scaffold(
          backgroundColor: ConsoleColors.canvas,
          appBar: AppBar(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            titleSpacing: isWide ? 24 : null,
            title: Text(
              sections[index].label,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
            actions: const [
              ConnectionStatusDot(),
              SizedBox(width: 4),
              AccountMenuButton(changePasswordRoute: '/admin/change-password'),
              SizedBox(width: 8),
            ],
          ),
          drawer: isWide
              ? null
              : Drawer(
                  backgroundColor: ConsoleColors.ink,
                  width: 264,
                  child: SafeArea(
                    child: _NavList(
                      sections: sections,
                      selectedIndex: index,
                      onSelect: (i) {
                        Navigator.of(context).pop();
                        select(i);
                      },
                    ),
                  ),
                ),
          body: isWide
              ? Row(
                  children: [
                    Container(
                      width: 236,
                      color: ConsoleColors.ink,
                      child: _NavList(
                        sections: sections,
                        selectedIndex: index,
                        onSelect: select,
                      ),
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: ConsoleColors.canvas,
                        child: sections[index].body,
                      ),
                    ),
                  ],
                )
              : ColoredBox(
                  color: ConsoleColors.canvas,
                  child: sections[index].body,
                ),
        );
      },
    );
  }
}

/// The Console's wayfinding surface - a fixed dark panel (not swapped by
/// theme preset, unlike the app bar above it) so the shell reads as one
/// stable control surface regardless of which brand color is active; the
/// active preset still shows through as the selected item's accent edge.
class _NavList extends StatelessWidget {
  const _NavList({
    required this.sections,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_AdminSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const _inkLight = Color(0xFFAEB4C4);

  @override
  Widget build(BuildContext context) {
    final opsCount = sections.where((s) => !s.superAdminOnly).length;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: ConsoleSpace.lg),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(ConsoleRadius.sm),
                ),
                child: Icon(
                  Icons.local_shipping_outlined,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'SuperDelivery',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < sections.length; i++) ...[
          if (i == opsCount && opsCount < sections.length)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(
                'ADMIN CONSOLE',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _inkLight,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          _NavItem(
            icon: sections[i].icon,
            label: sections[i].label,
            selected: selectedIndex == i,
            onTap: () => onSelect(i),
          ),
        ],
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : const Color(0xFFC2C7D6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 1, 10, 1),
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(ConsoleRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(ConsoleRadius.sm),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ConsoleRadius.sm),
              border: Border(
                left: BorderSide(
                  color: selected ? AppTheme.accent : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 6),
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
