import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/transaction_providers.dart';
import '../../data/transactions_repository.dart';
import '../../domain/finance_transaction.dart';
import '../transaction_form_sheet.dart';
import '../widgets/async_list_states.dart';
import '../widgets/transaction_tile.dart';

/// The transactions tab — a live list of every money movement, newest first.
class TransactionsTab extends ConsumerWidget {
  const TransactionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FinanceTransaction>> transactions = ref.watch(
      transactionsStreamProvider,
    );

    return Scaffold(
      // A nested Scaffold so this tab gets its own FAB. Transparent, because
      // the outer Scaffold already paints the background.
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showTransactionFormSheet(context),
        tooltip: 'Add transaction',
        child: const Icon(Icons.add),
      ),
      // All three states handled explicitly — the project rule, and `.when`
      // will not compile without them.
      body: transactions.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => FinanceErrorState(
          title: 'Could not load your transactions',
          error: error,
        ),
        data: (List<FinanceTransaction> items) {
          if (items.isEmpty) {
            return const FinanceEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              message: 'Tap + to log your first one. It appears on every '
                  'device you are signed in on, within seconds.',
            );
          }
          return _TransactionList(items: items);
        },
      ),
    );
  }
}

class _TransactionList extends ConsumerWidget {
  const _TransactionList({required this.items});

  final List<FinanceTransaction> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      // Clears the FAB, so the last row is never stuck underneath it.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: items.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1, color: AppColors.gridline),
      itemBuilder: (BuildContext context, int index) {
        final FinanceTransaction transaction = items[index];
        return Dismissible(
          // Keyed by document ID, not by list position: Firestore reorders the
          // list on every change, and a position key would animate the wrong
          // row away.
          key: ValueKey<String>(transaction.id),
          direction: DismissDirection.endToStart,
          background: const DeleteBackground(),
          onDismissed: (DismissDirection _) =>
              _deleteWithUndo(context, ref, transaction),
          child: TransactionTile(
            transaction: transaction,
            onTap: () =>
                showTransactionFormSheet(context, initial: transaction),
          ),
        );
      },
    );
  }

  /// Deletes immediately and offers an undo, rather than asking "are you sure?"
  ///
  /// A confirmation dialog costs a tap on every deliberate delete to guard
  /// against the rare accident. Undo reverses that: the common case is free,
  /// and the mistake is recoverable — including its original document ID, which
  /// is why the repository has a `restore` rather than a second `add`.
  Future<void> _deleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    FinanceTransaction transaction,
  ) async {
    final TransactionsRepository? repository = ref.read(
      transactionsRepositoryProvider,
    );
    if (repository == null) return;

    // Captured before the await: after it, this context may be gone.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await repository.delete(transaction.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Transaction deleted.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repository.restore(transaction),
            ),
          ),
        );
    } on FinanceFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
