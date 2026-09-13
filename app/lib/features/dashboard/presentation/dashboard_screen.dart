import 'package:flutter/material.dart';

import '../../../core/widgets/milestone_placeholder.dart';

/// The landing screen after sign-in.
///
/// Milestone 0 ships this empty on purpose — the "done when" for scaffolding is
/// *sign in and land on an empty dashboard shell*. The stat tiles (balance,
/// income vs expense, savings progress) are Milestone 1, computed live from the
/// Firestore transaction stream rather than stored.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: const MilestonePlaceholder(
        icon: Icons.dashboard_outlined,
        title: 'Dashboard',
        milestone: 'Milestone 1',
        description:
            'Balance, income vs expense, savings progress and total liabilities '
            '— all computed live from your transactions.',
      ),
    );
  }
}
