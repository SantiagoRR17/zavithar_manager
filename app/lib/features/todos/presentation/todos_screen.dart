import 'package:flutter/material.dart';

import '../../../core/widgets/milestone_placeholder.dart';

/// Categorised todos with deadlines, reminders and follow-up tasks.
///
/// Empty until Milestone 2. The four categories (work, hobbies, study, home)
/// already have their fixed colours reserved in `AppColors.categoryColors`.
class TodosScreen extends StatelessWidget {
  const TodosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      body: const MilestonePlaceholder(
        icon: Icons.checklist_outlined,
        title: 'Todos',
        milestone: 'Milestone 2',
        description:
            'Tasks by category with deadlines, priorities and follow-ups. '
            'Reminder pushes arrive in Milestone 3.',
      ),
    );
  }
}
