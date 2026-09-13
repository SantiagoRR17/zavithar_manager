import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/liabilities_repository.dart';
import '../data/savings_repository.dart';
import '../data/transactions_repository.dart';
import '../domain/finance_transaction.dart';
import '../domain/liability.dart';
import '../domain/savings_goal.dart';

/// Riverpod providers for the finance feature — the bridge between
/// `TransactionsRepository` (which knows Firestore) and the widgets (which must
/// not), exactly as `auth_providers.dart` does for auth.

/// The repository, rebuilt whenever the signed-in user changes.
///
/// Null when signed out, rather than throwing. Two reasons, and the second is
/// the important one:
///
/// 1. Signed out is a legitimate state, not an error. The auth gate means no
///    finance screen is ever *built* in it, but the provider graph is evaluated
///    slightly ahead of the widget tree, so it has to have an answer.
/// 2. Because this `watch`es the uid, signing out **disposes the old repository
///    and every stream derived from it.** Without that, the Firestore listener
///    opened for the previous user would keep running — still authorised,
///    because its token is still valid for a moment — and the next user's list
///    could briefly render the previous user's data. Rebuilding on uid is what
///    makes that impossible rather than unlikely.
final Provider<TransactionsRepository?> transactionsRepositoryProvider =
    Provider<TransactionsRepository?>((Ref ref) {
      final User? user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return TransactionsRepository(uid: user.uid);
    });

/// Every transaction, newest first, live.
///
/// A [StreamProvider] gives the screen an `AsyncValue<List<FinanceTransaction>>`
/// — loading, error, or data, with the compiler refusing to let any of the
/// three go unhandled. That is the project rule about explicit loading/error
/// states, enforced by the type rather than by discipline (see lesson 02).
///
/// Riverpod cancels the underlying Firestore listener when nothing is watching
/// this any more, so navigating away from the Finance tab stops the reads. That
/// matters for NFR-5: Firestore bills per document read, and a listener left
/// open on a collection is a slow leak of the free tier.
final StreamProvider<List<FinanceTransaction>> transactionsStreamProvider =
    StreamProvider<List<FinanceTransaction>>((Ref ref) {
      final TransactionsRepository? repository = ref.watch(
        transactionsRepositoryProvider,
      );
      if (repository == null) {
        return const Stream<List<FinanceTransaction>>.empty();
      }
      return repository.watchAll();
    });

// --- Savings goals ---------------------------------------------------------
//
// The same two-provider shape as transactions above, and for the same reasons.
// Repeated rather than abstracted: three near-identical pairs are easier to
// read and change than one generic factory, and they will stop being identical
// as soon as savings grows filtering that transactions does not need.

final Provider<SavingsRepository?> savingsRepositoryProvider =
    Provider<SavingsRepository?>((Ref ref) {
      final User? user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return SavingsRepository(uid: user.uid);
    });

final StreamProvider<List<SavingsGoal>> savingsStreamProvider =
    StreamProvider<List<SavingsGoal>>((Ref ref) {
      final SavingsRepository? repository = ref.watch(savingsRepositoryProvider);
      if (repository == null) return const Stream<List<SavingsGoal>>.empty();
      return repository.watchAll();
    });

// --- Liabilities -----------------------------------------------------------

final Provider<LiabilitiesRepository?> liabilitiesRepositoryProvider =
    Provider<LiabilitiesRepository?>((Ref ref) {
      final User? user = ref.watch(currentUserProvider);
      if (user == null) return null;
      return LiabilitiesRepository(uid: user.uid);
    });

final StreamProvider<List<Liability>> liabilitiesStreamProvider =
    StreamProvider<List<Liability>>((Ref ref) {
      final LiabilitiesRepository? repository = ref.watch(
        liabilitiesRepositoryProvider,
      );
      if (repository == null) return const Stream<List<Liability>>.empty();
      return repository.watchAll();
    });
