import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/recurring_repository.dart';
import '../domain/recurring_rule.dart';
import 'statement_providers.dart';

/// Providers for recurring transactions.

final Provider<RecurringRepository?> recurringRepositoryProvider =
    Provider<RecurringRepository?>((Ref ref) {
      final User? user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return RecurringRepository(uid: user.uid);
    });

final StreamProvider<List<RecurringRule>> recurringStreamProvider =
    StreamProvider<List<RecurringRule>>((Ref ref) {
      final RecurringRepository? repository = ref.watch(
        recurringRepositoryProvider,
      );
      if (repository == null) {
        return const Stream<List<RecurringRule>>.empty();
      }
      return repository.watchAll();
    });

/// What each rule owes right now, without writing anything.
///
/// Separating "work out what is due" from "create it" is what lets the screen
/// show *"3 transactions will be created"* before anything happens, and what
/// makes the arithmetic testable without a database.
final Provider<List<RecurrenceRun>> pendingRecurrenceProvider =
    Provider<List<RecurrenceRun>>((Ref ref) {
      final List<RecurringRule> rules =
          ref.watch(recurringStreamProvider).asData?.value ??
          const <RecurringRule>[];
      final DateTime? openFrom = ref.watch(openPeriodStartProvider);

      return <RecurrenceRun>[
        for (final RecurringRule rule in rules)
          RecurrenceSchedule.due(rule, openPeriodStart: openFrom),
      ];
    });

/// How many transactions are waiting to be created.
final Provider<int> pendingRecurrenceCountProvider = Provider<int>((Ref ref) {
  return ref
      .watch(pendingRecurrenceProvider)
      .fold<int>(0, (int sum, RecurrenceRun r) => sum + r.dates.length);
});

/// Occurrences that cannot be created because their month is already closed.
final Provider<int> skippedRecurrenceCountProvider = Provider<int>((Ref ref) {
  return ref
      .watch(pendingRecurrenceProvider)
      .fold<int>(0, (int sum, RecurrenceRun r) => sum + r.skippedClosed);
});

/// Creates everything that is due, one rule at a time.
///
/// **Deliberately not automatic.** Materialising on app launch is the obvious
/// design and it is the wrong one here: the app runs on two devices against one
/// database, so two launches minutes apart could each decide the same rent is
/// owed. Firestore has no lock the client can take, and the batch is atomic per
/// rule but not across devices.
///
/// A person pressing a button that says *"create 3 transactions"* cannot
/// produce that race, sees what is about to happen before it happens, and can
/// undo it afterwards because the results are ordinary transactions. The cost
/// is one tap a month; the alternative is duplicated rent, which is the single
/// fastest way to make someone stop trusting a finance app.
final Provider<Future<int> Function()> runRecurrenceProvider =
    Provider<Future<int> Function()>((Ref ref) {
      return () async {
        final RecurringRepository? repository = ref.read(
          recurringRepositoryProvider,
        );
        if (repository == null) return 0;

        int created = 0;
        for (final RecurrenceRun run in ref.read(pendingRecurrenceProvider)) {
          if (!run.hasWork && run.nextRunAt == run.rule.nextRunAt) continue;
          try {
            await repository.materialise(run);
            created += run.dates.length;
          } catch (error) {
            // One rule failing must not stop the rest: a rent charge refused
            // because its month is closed should not also prevent the salary
            // from being recorded.
            debugPrint('Recurring rule ${run.rule.id} failed: $error');
          }
        }
        return created;
      };
    });
