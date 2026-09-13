import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/transaction_providers.dart';
import '../../data/savings_repository.dart';
import '../../data/transactions_repository.dart' show FinanceFailure;
import '../../domain/savings_goal.dart';
import '../savings_form_sheet.dart';
import '../widgets/async_list_states.dart';
import '../widgets/savings_goal_card.dart';

/// The savings tab — every goal with its progress, live.
class SavingsTab extends ConsumerWidget {
  const SavingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SavingsGoal>> goals = ref.watch(
      savingsStreamProvider,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showSavingsFormSheet(context),
        tooltip: 'New savings goal',
        child: const Icon(Icons.add),
      ),
      body: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => FinanceErrorState(
          title: 'Could not load your savings goals',
          error: error,
        ),
        data: (List<SavingsGoal> items) {
          if (items.isEmpty) {
            return const FinanceEmptyState(
              icon: Icons.savings_outlined,
              title: 'Nothing being saved for yet',
              message: 'Tap + to set a target. Add to it whenever you put '
                  'money aside, and watch the bar fill.',
            );
          }
          return _SavingsList(items: items);
        },
      ),
    );
  }
}

class _SavingsList extends ConsumerWidget {
  const _SavingsList({required this.items});

  final List<SavingsGoal> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final SavingsGoal goal = items[index];
        return Dismissible(
          key: ValueKey<String>(goal.id),
          direction: DismissDirection.endToStart,
          background: const DeleteBackground(),
          onDismissed: (DismissDirection _) =>
              _deleteWithUndo(context, ref, goal),
          child: SavingsGoalCard(
            goal: goal,
            onContribute: () => showContributeSheet(context, goal),
            onTap: () => showSavingsFormSheet(context, initial: goal),
          ),
        );
      },
    );
  }

  Future<void> _deleteWithUndo(
    BuildContext context,
    WidgetRef ref,
    SavingsGoal goal,
  ) async {
    final SavingsRepository? repository = ref.read(savingsRepositoryProvider);
    if (repository == null) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await repository.delete(goal.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('"${goal.name}" deleted.'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repository.restore(goal),
            ),
          ),
        );
    } on FinanceFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
