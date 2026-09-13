import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';

/// Entry point.
///
/// Two things have to happen before the first frame:
///   1. Firebase is initialised — nothing that touches Auth or Firestore works
///      until it is, and the router asks for auth state immediately.
///   2. Firestore's offline cache is switched on, which is what satisfies the
///      "app keeps working offline and reconciles later" requirement (FR-18,
///      NFR-3).
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

  // ProviderScope is where Riverpod stores every provider's state. It has to
  // sit above anything that reads a provider, so it wraps the whole app.
  runApp(const ProviderScope(child: ZavitharManagerApp()));
}

class ZavitharManagerApp extends ConsumerWidget {
  const ZavitharManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);

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
