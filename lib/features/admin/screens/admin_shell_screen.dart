import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/user_role.dart';
import '../../../models/vendor.dart';
import '../../../shared/widgets/account_menu_button.dart';
import '../../console/screens/console_audit_log_tab.dart';
import '../../console/screens/console_commission_tab.dart';
import '../../console/screens/console_daily_fees_tab.dart';
import '../../console/screens/console_finance_tab.dart';
import '../../console/screens/console_notices_tab.dart';
import '../../console/screens/console_reports_tab.dart';
import '../../console/screens/console_onboarding_tab.dart';
import '../../console/screens/console_overview_tab.dart';
import '../../console/screens/console_settings_tab.dart';
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
/// Team and the remaining Console sections (Overview, Reports, Finance,
/// Audit log, Onboarding, Zones, Settings) - an auditor can view every one
/// of these but can't write to the admin-level ones (dispatcher/super-admin
/// management is exclusive to a super admin, so is the rest of Team; an
/// auditor's own read-only access is enforced server-side, not just by
/// hiding buttons - see `0054_auditor_role_permissions.sql`). See
/// [DriversScreen] for why the driver roster is split out into its own
/// section instead of living under Team.
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
      Icons.insights_outlined,
      'Overview',
      ConsoleOverviewTab(),
      superAdminOnly: true,
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
        final canViewAdminSections = myRole?.canViewAdminConsole ?? false;

        // The full delivery list re-emits on every change - diffing by id
        // tells apart a genuinely new order (never seen this id before)
        // from an existing delivery whose status just changed. previous ==
        // null (still loading) is skipped so the first load doesn't fire
        // one notification per already-existing delivery.
        ref.listen<AsyncValue<List<Delivery>>>(allDeliveriesProvider, (
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
            if (!section.superAdminOnly || canViewAdminSections) section,
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

        final sections = [
          _AdminSection(
            Icons.dashboard_outlined,
            'Home',
            HomeScreen(
              quickLinks: [
                for (final section in restOfSections)
                  DashboardQuickLink(section.icon, section.label),
              ],
              onNavigate: goToLabel,
            ),
          ),
          ...restOfSections,
        ];
        final index = _index.clamp(0, sections.length - 1);
        final isWide = MediaQuery.sizeOf(context).width >= 900;

        void select(int i) => setState(() => _index = i);

        return Scaffold(
          appBar: AppBar(
            title: Text(sections[index].label),
            actions: const [
              AccountMenuButton(changePasswordRoute: '/admin/change-password'),
            ],
          ),
          drawer: isWide
              ? null
              : Drawer(
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
                    SizedBox(
                      width: 220,
                      child: _NavList(
                        sections: sections,
                        selectedIndex: index,
                        onSelect: select,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: sections[index].body),
                  ],
                )
              : sections[index].body,
        );
      },
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({
    required this.sections,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_AdminSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final opsCount = sections.where((s) => !s.superAdminOnly).length;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i == opsCount && opsCount < sections.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                'ADMIN CONSOLE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ListTile(
            leading: Icon(
              sections[i].icon,
              color: selectedIndex == i
                  ? AppTheme.primary
                  : Colors.grey.shade600,
            ),
            title: Text(
              sections[i].label,
              style: TextStyle(
                fontWeight: selectedIndex == i
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: selectedIndex == i ? AppTheme.primary : Colors.black87,
              ),
            ),
            selected: selectedIndex == i,
            selectedTileColor: AppTheme.primaryLight,
            onTap: () => onSelect(i),
          ),
        ],
      ],
    );
  }
}
