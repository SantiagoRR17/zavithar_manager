import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/notifications/application/notification_providers.dart';
import 'firebase_options.dart';

/// Entry point.
///
/// Exactly two things happen before the first frame, and the list is short on
/// purpose — anything awaited here can prevent the app from rendering at all:
///   1. Firebase is initialised — nothing that touches Auth or Firestore works
///      until it is, and the router asks for auth state immediately.
///   2. Firestore's offline cache is switched on, which is what satisfies the
///      "app keeps working offline and reconciles later" requirement (FR-18,
///      NFR-3).
///
/// Notifications are deliberately **not** in that list: they initialise lazily,
/// so that nothing optional can stop the app from opening.
Future<void> main() async {
  // Required before any plugin call that happens before `runApp` — it wires up
  // the channel Flutter uses to talk to the platform.
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Firestore keeps a local copy of everything it has seen. Reads are served
  // from it instantly, writes are queued while offline and replayed on
  // reconnect. `unlimited` cache size is fine for a single user's finance and
  // todo data.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Firestore's own RPC logging. Off by default because it is extremely noisy,
  // but kept rather than deleted: on 2026-09-13 a todo disappeared between
  // sessions and this was the only thing that could say whether a write had
  // been acknowledged by the server, rejected by the rules, or left queued in
  // the local cache. **The UI looks identical in all three**, because latency
  // compensation shows the row either way — so without this there is no
  // difference between "saved" and "about to vanish".
  //
  // Flip to `kDebugMode` and watch for `commit_time` (accepted) or
  // `permission-denied` (rejected) after a write.
  const bool logFirestoreRpcs = false;
  // ignore: dead_code
  if (logFirestoreRpcs) FirebaseFirestore.setLoggingEnabled(kDebugMode);

  // ProviderScope is where Riverpod stores every provider's state. It has to
  // sit above anything that reads a provider, so it wraps the whole app.
  //
  // **Nothing optional is awaited before this line.** An earlier version
  // initialised the notification plugin here first, and when that threw — the
  // release build's resource shrinker had deleted the notification icon, which
  // makes `initialize` fail — the app never rendered. It sat on the splash
  // screen forever with no visible error, because `runApp` was never reached.
  //
  // Notifications now initialise lazily, inside the service, the first time
  // reminders are actually synced. A failure there costs reminders; it cannot
  // cost the app.
  runApp(const ProviderScope(child: ZavitharManagerApp()));
}

class ZavitharManagerApp extends ConsumerWidget {
  const ZavitharManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);

    // Keeps Android's alarms in step with the todos, for the whole life of the
    // app rather than only while the Todos tab is on screen. See
    // `reminderSyncProvider` for why that distinction matters on a two-device
    // app.
    ref.watch(reminderSyncProvider);

    // `.router` rather than the plain constructor: it hands navigation over to
    // go_router, so the auth-gate redirect in `app_router.dart` runs for every
    // navigation, including deep links.
    return MaterialApp.router(
      title: 'Zavithar Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // Dark-only for now; a light theme is a Milestone 4 concern.
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
