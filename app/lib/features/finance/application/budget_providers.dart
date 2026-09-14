import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/budgets_repository.dart';
import '../domain/budget.dart';
import '../domain/finance_transaction.dart';
import 'transaction_providers.dart';

/// Providers for monthly budgets.

final Provider<BudgetsRepository?> budgetsRepositoryProvider =
    Provider<BudgetsRepository?>((Ref ref) {
      final User? user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return BudgetsRepository(uid: user.uid);
    });

final StreamProvider<List<Budget>> budgetsStreamProvider =
    StreamProvider<List<Budget>>((Ref ref) {
      final BudgetsRepository? repository = ref.watch(
        budgetsRepositoryProvider,
      );
      if (repository == null) return const Stream<List<Budget>>.empty();
      return repository.watchAll();
    });

/// Each budget paired with what has been spent against it this month.
///
/// A fold of two streams that already exist, so no third Firestore listener is
/// opened — the same reasoning as `financeSummaryProvider`. The transactions
/// stream carries the open period (ADR 0012), which always includes the current
/// month, so the spending figures are complete even after a close.
final Provider<List<BudgetStatus>> budgetStatusProvider =
    Provider<List<BudgetStatus>>((Ref ref) {
      final List<Budget> budgets =
          ref.watch(budgetsStreamProvider).asData?.value ?? const <Budget>[];
      final List<FinanceTransaction> transactions =
          ref.watch(transactionsStreamProvider).asData?.value ??
          const <FinanceTransaction>[];

      return BudgetReport.from(budgets: budgets, transactions: transactions);
    });

/// How many budgets are currently exceeded, for the dashboard.
final Provider<int> budgetsOverCountProvider = Provider<int>((Ref ref) {
  return BudgetReport.overCount(ref.watch(budgetStatusProvider));
});
