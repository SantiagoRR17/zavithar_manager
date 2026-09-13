import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../finance/application/transaction_providers.dart';
import '../../finance/domain/finance_transaction.dart';
import '../../finance/domain/liability.dart';
import '../../finance/domain/savings_goal.dart';
import '../domain/finance_summary.dart';

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
      if (!transactions.hasValue || !savings.hasValue || !liabilities.hasValue) {
        return const AsyncValue<FinanceSummary>.loading();
      }

      return AsyncValue<FinanceSummary>.data(
        FinanceSummary.from(
          transactions: transactions.requireValue,
          savings: savings.requireValue,
          liabilities: liabilities.requireValue,
        ),
      );
    });
