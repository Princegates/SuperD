import 'package:flutter/material.dart';

import 'console_audit_log_tab.dart';
import 'console_finance_tab.dart';
import 'console_onboarding_tab.dart';
import 'console_overview_tab.dart';
import 'console_zones_tab.dart';

/// The super-admin back office: reporting, finance, an audit trail, and a
/// unified view of staff/vendor onboarding - everything that doesn't
/// belong on the day-to-day dispatch board. Only reachable at
/// `/admin/console`, which the router restricts to `super_admin`.
class ConsoleScreen extends StatefulWidget {
  const ConsoleScreen({super.key});

  @override
  State<ConsoleScreen> createState() => _ConsoleScreenState();
}

class _ConsoleSection {
  const _ConsoleSection(this.icon, this.label, this.child);
  final IconData icon;
  final String label;
  final Widget child;
}

class _ConsoleScreenState extends State<ConsoleScreen> {
  int _index = 0;

  static const _sections = [
    _ConsoleSection(Icons.insights_outlined, 'Overview', ConsoleOverviewTab()),
    _ConsoleSection(Icons.payments_outlined, 'Finance', ConsoleFinanceTab()),
    _ConsoleSection(
      Icons.receipt_long_outlined,
      'Audit log',
      ConsoleAuditLogTab(),
    ),
    _ConsoleSection(
      Icons.how_to_reg_outlined,
      'Onboarding',
      ConsoleOnboardingTab(),
    ),
    _ConsoleSection(Icons.map_outlined, 'Zones', ConsoleZonesTab()),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 760;

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Console')),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final section in _sections)
                      NavigationRailDestination(
                        icon: Icon(section.icon),
                        label: Text(section.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _sections[_index].child),
              ],
            )
          : _sections[_index].child,
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final section in _sections)
                  NavigationDestination(
                    icon: Icon(section.icon),
                    label: section.label,
                  ),
              ],
            ),
    );
  }
}
