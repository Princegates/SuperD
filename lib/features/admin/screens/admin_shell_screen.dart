import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/user_role.dart';
import '../../../shared/widgets/account_menu_button.dart';
import '../../console/screens/console_audit_log_tab.dart';
import '../../console/screens/console_finance_tab.dart';
import '../../console/screens/console_onboarding_tab.dart';
import '../../console/screens/console_overview_tab.dart';
import '../../console/screens/console_zones_tab.dart';
import '../providers/admin_providers.dart';
import 'admin_dashboard_screen.dart';
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

  /// Reporting/finance/audit/onboarding/zones are super-admin only -
  /// dispatchers never see these in the nav at all, on top of the RLS that
  /// already keeps their underlying data out of reach either way.
  final bool superAdminOnly;
}

/// The whole back-office experience in one place: every section a
/// dispatcher or super admin can reach, behind a single persistent
/// navigation surface instead of separate full-screen pages you push into
/// and back out of. What shows up in the nav is role-based - a dispatcher
/// sees Deliveries/Team/Vendors; a super admin also sees the Console
/// sections (Overview, Finance, Audit log, Onboarding, Zones).
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _index = 0;

  static const _restOfSections = [
    _AdminSection(
      Icons.local_shipping_outlined,
      'Deliveries',
      AdminDashboardScreen(),
    ),
    _AdminSection(Icons.groups_outlined, 'Team', TeamScreen()),
    _AdminSection(Icons.storefront_outlined, 'Vendors', VendorsScreen()),
    _AdminSection(Icons.near_me_outlined, 'Live Map', LiveMapScreen()),
    _AdminSection(
      Icons.insights_outlined,
      'Overview',
      ConsoleOverviewTab(),
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
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final isSuperAdmin =
            ref.watch(currentProfileProvider).valueOrNull?.role ==
            UserRole.superAdmin;

        // The full delivery list re-emits on every change - only ids that
        // weren't there last time are a genuinely new order, whether it
        // came from a vendor's customer link or was created here directly.
        // previous == null (still loading) is skipped so the first load
        // doesn't fire one notification per already-existing delivery.
        ref.listen<AsyncValue<List<Delivery>>>(allDeliveriesProvider, (
          previous,
          next,
        ) {
          final priorIds = previous?.valueOrNull?.map((d) => d.id).toSet();
          final current = next.valueOrNull;
          if (priorIds == null || current == null) return;
          for (final delivery in current) {
            if (delivery.status == DeliveryStatus.pending &&
                !priorIds.contains(delivery.id)) {
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
          }
        });

        final restOfSections = [
          for (final section in _restOfSections)
            if (!section.superAdminOnly || isSuperAdmin) section,
        ];

        void goToLabel(String label) {
          final i = restOfSections.indexWhere((s) => s.label == label);
          if (i != -1) setState(() => _index = i + 1);
        }

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
