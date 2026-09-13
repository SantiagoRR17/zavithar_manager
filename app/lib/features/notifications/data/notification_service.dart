import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_plan.dart';

/// The only place in the app that talks to the notification plugin.
///
/// Same rule as the Firestore repositories: nothing above this layer knows the
/// plugin exists, so the scheduling *policy* — which reminders, when, how many —
/// stays in `ReminderPlan`, where it can be tested without a device.
///
/// See [ADR 0011](../../../../docs/adr/0011-free-tier-only.md): there is no
/// server in this design. Every alarm below is registered with Android by this
/// device, from the todos Firestore has already synced to it.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;
  bool _initialising = false;
  bool _failed = false;

  /// Android needs a channel before anything can be posted on API 26+.
  ///
  /// The ID is baked in rather than derived: **a channel's settings are frozen
  /// once created.** Changing the importance later does nothing for anyone who
  /// already has the app installed — the only way to alter it is to ship a new
  /// channel ID, which is a decision worth making deliberately rather than by
  /// editing a constant.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'todo_reminders',
    'Task reminders',
    description: 'Reminders for tasks with a time set.',
    // `high` is what makes a reminder appear as a heads-up banner rather than
    // arriving silently in the shade. A reminder nobody sees is not a reminder.
    importance: Importance.high,
  );

  /// Sets up time zones and the channel. Safe to call more than once.
  ///
  /// **The time zone database is the part that is easy to skip and fatal.**
  /// `zonedSchedule` takes a `TZDateTime`, and without `initializeTimeZones` the
  /// `tz` package has no locations at all, so building one throws. Setting the
  /// *local* location matters just as much: left at the default UTC, a reminder
  /// for 09:00 in Bogotá would fire at 04:00.
  /// Initialises if it has not been, and reports whether it worked.
  ///
  /// **Nothing may await this before the first frame.** An earlier version was
  /// called from `main()` ahead of `runApp()`, and when it threw — a
  /// notification icon the release build's resource shrinker had deleted —
  /// the app never rendered at all. It sat on the splash screen forever, with
  /// no error a user could see. A reminder icon is not worth the app failing to
  /// open, and nothing optional should ever be able to hold the UI hostage.
  Future<bool> ensureInitialized({
    DidReceiveNotificationResponseCallback? onTap,
  }) async {
    if (_ready) return true;
    if (_failed || _initialising) return false;
    _initialising = true;
    try {
      await initialize(onTap: onTap);
      return _ready;
    } catch (error, stack) {
      // Swallowed on purpose, and remembered: retrying a broken plugin setup on
      // every todo change would just log the same failure forever.
      _failed = true;
      debugPrint('Notifications unavailable: $error');
      debugPrint('$stack');
      return false;
    } finally {
      _initialising = false;
    }
  }

  Future<void> initialize({
    DidReceiveNotificationResponseCallback? onTap,
  }) async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    try {
      final TimezoneInfo info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (error) {
      // An unknown IANA name would otherwise throw here and take down startup.
      // UTC is wrong but survivable — reminders fire at the wrong hour rather
      // than the app failing to open, and the wrong hour is visible where a
      // crash-on-launch is merely baffling.
      debugPrint('Could not resolve the local time zone ($error); using UTC.');
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        // **Not the launcher icon.** Android throws away the colour of a
        // status-bar icon and keeps only its alpha channel, so a full-colour
        // launcher icon arrives as a featureless white blob. `ic_stat_zavithar`
        // is the same Z drawn as pure white on transparency, which is what the
        // platform actually wants.
        android: AndroidInitializationSettings('@drawable/ic_stat_zavithar'),
      ),
      onDidReceiveNotificationResponse: onTap,
    );

    await _android?.createNotificationChannel(_channel);
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Whether notifications are currently permitted. **Asks nothing** — this is
  /// the query, and [requestPermission] is the action.
  ///
  /// Keeping them apart matters more than it looks. Merging them means that
  /// merely *reading* the status pops a system dialog, so opening a settings
  /// screen to see whether reminders work would demand an answer instead of
  /// giving one.
  Future<bool> isPermitted() async {
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Asks for the runtime notification permission (Android 13+).
  ///
  /// Returns false if the user declines. Worth handling rather than ignoring:
  /// **scheduling succeeds whether or not this was granted** — the alarms are
  /// registered, they simply never become visible. Without checking, a silent
  /// refusal is indistinguishable from a bug in the scheduling.
  Future<bool> requestPermission() async {
    final bool? granted = await _android?.requestNotificationsPermission();
    return granted ?? false;
  }

  /// Whether Android will let this app set alarms that fire at a precise time.
  Future<bool> canScheduleExact() async {
    return await _android?.canScheduleExactNotifications() ?? false;
  }

  /// Opens the system screen where exact alarms are allowed.
  Future<void> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
  }

  /// Makes the device's registered alarms match [reminders].
  ///
  /// A diff rather than "cancel everything, then reschedule". The blunt version
  /// leaves a window in which no alarm exists at all, and if the process is
  /// killed inside it — which Android does freely — every reminder is silently
  /// gone. Cancelling only what is no longer wanted has no such window.
  ///
  /// Wanted reminders are re-registered every time regardless, because
  /// scheduling an existing ID replaces it: that is how an edited title or a
  /// moved time reaches an alarm that was already set.
  Future<void> sync(List<ScheduledReminder> reminders) async {
    // Initialised here rather than at startup, so the cost — and any failure —
    // lands on the feature that needs it instead of on the app opening.
    if (!await ensureInitialized()) return;

    final bool exact = await canScheduleExact();

    final List<PendingNotificationRequest> pending = await _plugin
        .pendingNotificationRequests();
    final Set<int> wanted = reminders
        .map((ScheduledReminder r) => r.id)
        .toSet();

    for (final PendingNotificationRequest p in pending) {
      if (!wanted.contains(p.id)) {
        await _plugin.cancel(id: p.id);
      }
    }

    for (final ScheduledReminder reminder in reminders) {
      await _schedule(reminder, exact: exact);
    }
  }

  Future<void> _schedule(
    ScheduledReminder reminder, {
    required bool exact,
  }) async {
    await _plugin.zonedSchedule(
      id: reminder.id,
      title: reminder.title,
      body: reminder.body,
      // The todo's document ID travels with the notification so that tapping it
      // can open that specific task rather than just the app.
      payload: reminder.todoId,
      scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // Falls back to inexact when the user has not allowed exact alarms.
      // Inexact still fires — Doze may just delay it, by minutes or by hours.
      // Refusing to schedule at all would turn a late reminder into no reminder,
      // which is strictly worse.
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// What the device is currently holding. Used by the diagnostics in Settings,
  /// because "did it actually get scheduled" is otherwise unanswerable until
  /// the moment it was supposed to fire.
  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();

  Future<void> cancelAll() => _plugin.cancelAll();
}
