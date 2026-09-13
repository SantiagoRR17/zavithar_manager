import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/transaction_providers.dart';
import '../../data/liabilities_repository.dart';
import '../../data/transactions_repository.dart' show FinanceFailure;
import '../../domain/liability.dart';
import '../liability_form_sheet.dart';
import '../widgets/async_list_states.dart';
import '../widgets/liability_card.dart';

/// The debts tab — every liability, biggest first, live.
class LiabilitiesTab extends ConsumerWidget {
  const LiabilitiesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Liability>> liabilities = ref.watch(
      liabilitiesStreamProvider,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showLiabilityFormSheet(context),
        tooltip: 'New liability',
        child: const Icon(Icons.add),
      ),
      body: liabilities.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => FinanceErrorState(
          title: 'Could not load your debts',
          error: error,
        ),
        data: (List<Liability> items) {
          if (items.isEmpty) {
            return const FinanceEmptyState(
              icon: Icons.credit_card_off_outlined,
              title: 'No debts recorded',
              message: 'A good place to be. Tap + if there is a loan or card '
                  'balance worth tracking.',
            );
          }
          return _LiabilitiesList(items: items);
        },
      ),
    );
  }
}

class _LiabilitiesList extends ConsumerWidget {
  const _LiabilitiesList({required this.items});

  final List<Liability> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final Liability liability = items[index];
        return Dismissible(
          key: ValueKey<String>(liability.id),
          direction: DismissDirection.endToStart,
          background: const DeleteBackground(),
          onDismissed: (DismissDirection _) =>
              _deleteWithUndo(context, ref, liability),
          child: LiabilityCard(
            liability: liability,
            onPay: () => showPaymentSheet(context, liability),
            onTap: () => showLiabilityFormSheet(context, initial: liability),
          ),
        );
      },
    );
  }

  Future<void> _deleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    Liability liability,
  ) async {
    final LiabilitiesRepository? repository = ref.read(
      liabilitiesRepositoryProvider,
    );
    if (repository == null) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await repository.delete(liability.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('"${liability.name}" deleted.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repository.restore(liability),
            ),
          ),
        );
    } on FinanceFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
