import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/app_colors.dart';
import '../application/notification_providers.dart';
import '../data/notification_service.dart';
import '../domain/reminder_plan.dart';

/// Reminder status and diagnostics, for the Settings screen.
///
/// This exists because **a reminder that was never scheduled looks exactly like
/// one that has not fired yet.** There is no screen on which the difference is
/// visible, and no error anywhere; the first symptom is silence on the day it
/// mattered. So the app says out loud what it is holding, and what would stop
/// it working.
class ReminderSettingsCard extends ConsumerStatefulWidget {
  const ReminderSettingsCard({super.key});

  @override
  ConsumerState<ReminderSettingsCard> createState() =>
      _ReminderSettingsCardState();
}

class _ReminderSettingsCardState extends ConsumerState<ReminderSettingsCard> {
  List<PendingNotificationRequest>? _pending;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<NotificationStatus> status = ref.watch(
      notificationStatusProvider,
    );
    final List<ScheduledReminder> plan = ref.watch(reminderPlanProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gridline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(
                Icons.notifications_active_outlined,
                size: 18,
                color: AppColors.brandPrimary,
              ),
              SizedBox(width: 8),
              Text(
                'Task reminders',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Scheduled on this device, from the tasks that have a reminder '
            'time. There is no server involved.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),

          status.when(
            loading: () => const _StatusLine(
              icon: Icons.hourglass_empty,
              text: 'Checking permissions…',
              color: AppColors.muted,
            ),
            error: (Object e, StackTrace _) => _StatusLine(
              icon: Icons.error_outline,
              text: 'Could not read notification permissions: $e',
              color: AppColors.statusCritical,
            ),
            data: (NotificationStatus s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _StatusLine(
                  icon: s.allowed
                      ? Icons.check_circle_outline
                      : Icons.block_outlined,
                  text: s.allowed
                      ? 'Notifications allowed'
                      : 'Notifications are blocked — reminders will be '
                            'scheduled but never shown',
                  color: s.allowed
                      ? AppColors.statusGood
                      : AppColors.statusCritical,
                ),
                const SizedBox(height: 6),
                _StatusLine(
                  icon: s.exact ? Icons.alarm_on : Icons.alarm_off,
                  text: s.exact
                      ? 'Exact timing allowed'
                      : 'Exact alarms not allowed — reminders may arrive late',
                  color: s.exact
                      ? AppColors.statusGood
                      : AppColors.statusWarning,
                ),
                if (!s.allowed) ...<Widget>[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _requestPermission,
                    icon: const Icon(Icons.notifications_active, size: 18),
                    label: const Text('Allow notifications'),
                  ),
                ],
                if (s.allowed && !s.exact) ...<Widget>[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _openExactAlarmSettings,
                    icon: const Icon(Icons.alarm_add, size: 18),
                    label: const Text('Allow exact alarms'),
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 24, color: AppColors.gridline),

          _StatusLine(
            icon: Icons.event_note_outlined,
            text: plan.isEmpty
                ? 'Nothing to remind you about yet'
                : '${plan.length} reminder${plan.length == 1 ? '' : 's'} '
                      'queued · next ${AppDates.shortWithTime(plan.first.at)}',
            color: AppColors.textSecondary,
          ),

          if (_pending != null) ...<Widget>[
            const SizedBox(height: 10),
            // What Android *actually* holds, as opposed to what the app
            // intends. The two disagreeing is the failure this card exists to
            // make visible, and it cannot be seen any other way.
            _StatusLine(
              icon: _pending!.length == plan.length
                  ? Icons.verified_outlined
                  : Icons.report_problem_outlined,
              text: _pending!.length == plan.length
                  ? 'Android is holding all ${_pending!.length} of them'
                  : 'Android is holding ${_pending!.length}, the app expects '
                        '${plan.length}',
              color: _pending!.length == plan.length
                  ? AppColors.statusGood
                  : AppColors.statusWarning,
            ),
          ],

          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _loading ? null : _check,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Check what is actually scheduled'),
          ),
        ],
      ),
    );
  }

  Future<void> _check() async {
    setState(() => _loading = true);
    final NotificationService service = ref.read(notificationServiceProvider);
    final List<PendingNotificationRequest> pending = await service.pending();
    if (mounted) {
      setState(() {
        _pending = pending;
        _loading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    await ref.read(notificationServiceProvider).requestPermission();
    ref.invalidate(notificationStatusProvider);
  }

  Future<void> _openExactAlarmSettings() async {
    await ref.read(notificationServiceProvider).requestExactAlarms();
    // The permission is granted on a system screen, not in a dialog, so the
    // answer only exists once the user comes back. Invalidating re-asks rather
    // than assuming either outcome.
    ref.invalidate(notificationStatusProvider);
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }
}
