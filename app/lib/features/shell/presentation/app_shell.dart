import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';

/// The persistent chrome around the four main sections of the app.
///
/// Why this file exists: the mockups call for **bottom tabs on mobile and a
/// sidebar on desktop**, but they are the same four destinations either way.
/// Building two separate navigators would mean two places to keep in sync, so
/// this widget owns one list of destinations and picks the presentation from
/// the available width.
///
/// It is handed a [StatefulNavigationShell] by `StatefulShellRoute` in
/// `app_router.dart`. That object *is* the current tab state — it knows which
/// branch is active and how to switch, so this widget stores no state itself.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Below this width the sidebar would eat too much of the screen, so the app
  /// switches to bottom tabs. 600dp is Material's own phone/tablet split.
  static const double _wideLayoutBreakpoint = 600;

  static const List<_Destination> _destinations = <_Destination>[
    _Destination('Dashboard', Icons.dashboard_outlined, Icons.dashboard),
    _Destination(
      'Finance',
      Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet,
    ),
    _Destination('Todos', Icons.checklist_outlined, Icons.checklist),
    _Destination('Settings', Icons.settings_outlined, Icons.settings),
  ];

  /// Switches branch. `initialLocation: true` when re-tapping the current tab
  /// pops that branch back to its root — the standard "tap the tab you're on to
  /// go home" behaviour.
  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder gives the constraints this widget was actually given,
    // rather than the size of the whole window — so it stays correct inside a
    // split view or a resized desktop window.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth >= _wideLayoutBreakpoint;
        return isWide ? _buildWideLayout() : _buildNarrowLayout();
      },
    );
  }

  Widget _buildNarrowLayout() {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: <NavigationDestination>[
          for (final _Destination d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: _Wordmark(),
            ),
            destinations: <NavigationRailDestination>[
              for (final _Destination d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}

/// One navigation destination. Filled icons mark the selected tab so the
/// selection is legible without relying on the accent colour alone.
@immutable
class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Plain text branding. The logo mark is still undecided (`CLAUDE.md` → Brand),
/// and the decision was explicitly not allowed to block development, so the
/// wordmark stands in for it.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        Text(
          'ZAVITHAR',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            fontSize: 13,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'MANAGER',
          style: TextStyle(
            color: AppColors.brandPrimaryLight,
            fontWeight: FontWeight.w500,
            letterSpacing: 3,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
