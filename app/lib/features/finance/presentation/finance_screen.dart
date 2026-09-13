import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import 'tabs/liabilities_tab.dart';
import 'tabs/savings_tab.dart';
import 'tabs/transactions_tab.dart';

/// The finance area: transactions, savings goals and liabilities.
///
/// Three Firestore collections, three tabs, one screen. Each tab is backed by
/// its own live stream — a write from any device (or from the Firebase console)
/// arrives as a new snapshot and rebuilds only the tab that cares. Nothing here
/// fetches, and there is no refresh gesture anywhere because there is nothing
/// for one to do.
///
/// `DefaultTabController` rather than the app router: these are three views of
/// one feature, not three destinations. Keeping them off the router means the
/// bottom navigation bar still shows "Finance" as one place, which is how it
/// reads to the person using it.
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Finance'),
          bottom: const TabBar(
            // The brand red marks the active tab, matching the nav bar.
            indicatorColor: AppColors.brandPrimary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.muted,
            tabs: <Widget>[
              Tab(text: 'Transactions'),
              Tab(text: 'Savings'),
              Tab(text: 'Debts'),
            ],
          ),
        ),
        // Each tab owns its own FAB, because "add" means something different in
        // each — a transaction, a goal, a debt. A single shared button would
        // have to guess.
        body: const TabBarView(
          children: <Widget>[
            TransactionsTab(),
            SavingsTab(),
            LiabilitiesTab(),
          ],
        ),
      ),
    );
  }
}
