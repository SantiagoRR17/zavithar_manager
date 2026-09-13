import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/statements_repository.dart';
import '../domain/finance_transaction.dart';
import '../domain/monthly_statement.dart';
import '../domain/statement_period.dart';
import 'transaction_providers.dart';

/// Providers for monthly statements and, crucially, for the **open-period
/// boundary** that every transaction query now depends on.
///
/// See [ADR 0012](../../../../docs/adr/0012-monthly-statements.md).

final Provider<StatementsRepository?> statementsRepositoryProvider =
    Provider<StatementsRepository?>((Ref ref) {
      final User? user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return StatementsRepository(uid: user.uid);
    });

/// Every statement, newest first. Twelve documents a year — the cheap
/// collection this whole feature trades *into*.
final StreamProvider<List<MonthlyStatement>> statementsStreamProvider =
    StreamProvider<List<MonthlyStatement>>((Ref ref) {
      final StatementsRepository? repository = ref.watch(
        statementsRepositoryProvider,
      );
      if (repository == null) {
        return const Stream<List<MonthlyStatement>>.empty();
      }
      return repository.watchAll();
    });

/// The most recently closed month, or null if nothing has been closed.
///
/// Taken as the **maximum** period rather than the first element of the stream.
/// The stream is already ordered by `periodStart` descending so the two agree
/// today, but a balance that silently depends on a sort order somewhere else is
/// a fragile thing to build on.
final Provider<StatementPeriod?> lastClosedPeriodProvider =
    Provider<StatementPeriod?>((Ref ref) {
      final List<MonthlyStatement> statements =
          ref.watch(statementsStreamProvider).asData?.value ??
          const <MonthlyStatement>[];
      if (statements.isEmpty) return null;

      StatementPeriod latest = statements.first.period;
      for (final MonthlyStatement s in statements) {
        if (s.period > latest) latest = s.period;
      }
      return latest;
    });

/// The instant the open period begins: the day after the last closed month.
///
/// Null means "no boundary yet" — either nothing has been closed, or the
/// statements are still loading. Those two are distinguished by
/// [statementsStreamProvider]'s own state, which is what the transactions
/// stream checks before it decides whether to open a listener at all.
final Provider<DateTime?> openPeriodStartProvider = Provider<DateTime?>((
  Ref ref,
) {
  return ref.watch(lastClosedPeriodProvider)?.endExclusive;
});

/// The one month that may be closed next, or null if none may be.
///
/// **Only ever the earliest unclosed month that has fully ended**, which is what
/// keeps the chain contiguous. Letting a month be skipped would leave its
/// transactions before the open-period boundary and inside no statement, so
/// they would disappear from the balance altogether — the failure ADR 0012
/// calls out. Contiguity here is correctness, not tidiness.
///
/// With nothing closed yet, the candidate is the month of the oldest
/// transaction on record: there is no point writing empty statements for the
/// years before the ledger starts.
final Provider<StatementPeriod?> closablePeriodProvider =
    Provider<StatementPeriod?>((Ref ref) {
      final StatementPeriod? lastClosed = ref.watch(lastClosedPeriodProvider);

      final StatementPeriod? candidate;
      if (lastClosed != null) {
        candidate = lastClosed.next;
      } else {
        final List<FinanceTransaction> transactions =
            ref.watch(transactionsStreamProvider).asData?.value ??
            const <FinanceTransaction>[];
        if (transactions.isEmpty) return null;

        DateTime oldest = transactions.first.date;
        for (final FinanceTransaction tx in transactions) {
          if (tx.date.isBefore(oldest)) oldest = tx.date;
        }
        candidate = StatementPeriod.of(oldest);
      }

      // A month still running cannot be closed. Half a month's totals written
      // as if they were the whole month's is precisely the quiet wrongness this
      // feature exists to prevent.
      return candidate.hasEnded() ? candidate : null;
    });

/// The balance carried in from every closed month.
///
/// Summed from the statements rather than taken from the latest one's
/// `closingBalance`. Both should agree; summing is the version that *notices*
/// when they do not, because a missing month shows up as a discrepancy instead
/// of being invisibly skipped.
final Provider<num> closedBalanceProvider = Provider<num>((Ref ref) {
  final List<MonthlyStatement> statements =
      ref.watch(statementsStreamProvider).asData?.value ??
      const <MonthlyStatement>[];

  num total = 0;
  for (final MonthlyStatement s in statements) {
    total += s.net;
  }
  return total;
});

/// The statement about to be written for [closablePeriodProvider], built from
/// the transactions already in memory.
///
/// **No extra read.** The closable month is by definition the first month of
/// the open period, so its transactions are already in
/// [transactionsStreamProvider]. Fetching them again would be paying twice for
/// documents the device is holding.
final Provider<MonthlyStatement?> pendingStatementProvider =
    Provider<MonthlyStatement?>((Ref ref) {
      final StatementPeriod? period = ref.watch(closablePeriodProvider);
      if (period == null) return null;

      final List<FinanceTransaction> transactions =
          ref.watch(transactionsStreamProvider).asData?.value ??
          const <FinanceTransaction>[];

      return MonthlyStatement.from(
        period: period,
        transactions: transactions,
        openingBalance: ref.watch(closedBalanceProvider),
      );
    });
