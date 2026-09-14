import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../finance/application/statement_providers.dart';
import '../../finance/application/transaction_providers.dart';
import '../../finance/domain/finance_transaction.dart';
import '../../finance/domain/liability.dart';
import '../../finance/domain/savings_goal.dart';
import '../../finance/domain/monthly_statement.dart';
import '../domain/finance_summary.dart';
import '../domain/spending_insights.dart';

/// The dashboard's single source of truth, folded from the three finance
/// streams the Finance tab already uses.
///
/// Note what this provider does *not* do: it opens no Firestore listener of its
/// own. It watches the same three [StreamProvider]s the Finance tab watches, and
/// Riverpod caches a provider per its arguments — so with both screens alive
/// there are still exactly three listeners, not six. That is NFR-5 money:
/// Firestore bills per document read, and a duplicated listener doubles the
/// cost of every change for no benefit.
///
/// It is a plain [Provider] returning an `AsyncValue`, not a [StreamProvider],
/// because there is no new stream here — only a synchronous fold of three that
/// already exist. Wrapping it in a stream would add a scheduling hop and an
/// extra frame of staleness.
final Provider<AsyncValue<FinanceSummary>> financeSummaryProvider =
    Provider<AsyncValue<FinanceSummary>>((Ref ref) {
      final AsyncValue<List<FinanceTransaction>> transactions = ref.watch(
        transactionsStreamProvider,
      );
      final AsyncValue<List<SavingsGoal>> savings = ref.watch(
        savingsStreamProvider,
      );
      final AsyncValue<List<Liability>> liabilities = ref.watch(
        liabilitiesStreamProvider,
      );

      // --- Error beats loading, and the order is the whole point -----------
      //
      // The tempting shape is "if anything is loading, show a spinner; then
      // check for errors". It produces a screen that spins forever: a stream
      // rejected by a security rule is in the error state and never leaves it,
      // while a sibling that is merely slow is still loading — so the spinner
      // branch wins every frame and the real failure is never displayed.
      // Checking errors first means a broken collection is *reported* rather
      // than disguised as slowness.
      final List<AsyncValue<Object?>> slices = <AsyncValue<Object?>>[
        transactions,
        savings,
        liabilities,
      ];

      for (final AsyncValue<Object?> slice in slices) {
        if (slice.hasError) {
          return AsyncValue<FinanceSummary>.error(
            slice.error!,
            slice.stackTrace ?? StackTrace.empty,
          );
        }
      }

      // `hasValue` rather than `!isLoading`: a stream that is refreshing is
      // both loading *and* holding its previous value, and the dashboard
      // should keep showing the last good numbers through a refresh rather
      // than flashing back to a spinner on every incoming snapshot.
      //
      // (Signed out, the finance providers hand back an empty stream that never
      // emits, so this stays loading. The auth gate means no dashboard is ever
      // built in that state — see `transaction_providers.dart`.)
      if (!transactions.hasValue ||
          !savings.hasValue ||
          !liabilities.hasValue) {
        return const AsyncValue<FinanceSummary>.loading();
      }

      return AsyncValue<FinanceSummary>.data(
        FinanceSummary.from(
          transactions: transactions.requireValue,
          savings: savings.requireValue,
          liabilities: liabilities.requireValue,
          // The closed months' net. The transactions stream only carries the
          // open period now (ADR 0012), so without this the balance would
          // silently reset to zero the moment a month was closed — the most
          // alarming possible way for a cost optimisation to go wrong.
          openingBalance: ref.watch(closedBalanceProvider),
        ),
      );
    });

/// Spending per category for the current month, for the dashboard chart.
///
/// Folded from the transactions stream that already exists — no new listener,
/// and no new reads.
final Provider<List<CategorySpend>> categorySpendProvider =
    Provider<List<CategorySpend>>((Ref ref) {
      final List<FinanceTransaction> transactions =
          ref.watch(transactionsStreamProvider).asData?.value ??
          const <FinanceTransaction>[];
      return SpendingInsights.byCategory(transactions);
    });

/// Income and expense per month.
///
/// Closed months come from their statements, which is the payoff of ADR 0012 in
/// its clearest form: a year of history is a dozen documents instead of
/// thousands of transactions, and the chart costs nothing extra to draw.
final Provider<List<MonthlyTotals>> monthlyTotalsProvider =
    Provider<List<MonthlyTotals>>((Ref ref) {
      return SpendingInsights.byMonth(
        statements:
            ref.watch(statementsStreamProvider).asData?.value ??
            const <MonthlyStatement>[],
        openTransactions:
            ref.watch(transactionsStreamProvider).asData?.value ??
            const <FinanceTransaction>[],
      );
    });
