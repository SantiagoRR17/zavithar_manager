import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';

/// Riverpod providers for the auth feature — the bridge between the repository
/// (which knows Firebase) and the widgets (which must not).
///
/// Why providers at all: a provider is a lazily-created, cached, globally
/// reachable value that widgets can *watch*. Watching means the widget rebuilds
/// by itself when the value changes, so no screen has to manually subscribe to
/// a stream, hold the latest value in a field, and remember to cancel on
/// dispose. Riverpod does all three.

/// The repository instance. Everything else depends on this one, which is what
/// makes it a single override point in tests:
/// `ProviderScope(overrides: [authRepositoryProvider.overrideWithValue(fake)])`.
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) => AuthRepository());

/// Who is signed in, as a stream.
///
/// A [StreamProvider] exposes the stream as an `AsyncValue<User?>` — a value
/// that is *always* in exactly one of three states: loading, error, or data.
/// That is the mechanism behind the project rule that every stream-backed
/// screen has explicit loading and error states: `.when(...)` will not compile
/// unless all three are handled.
///
/// Note the distinction the type makes: `AsyncData(null)` means "we know, and
/// nobody is signed in", while `AsyncLoading()` means "Firebase is still
/// restoring the saved session, we don't know yet". Collapsing those two would
/// flash the login screen on every cold start.
final StreamProvider<User?> authStateChangesProvider = StreamProvider<User?>(
  (Ref ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// The signed-in user, or `null` while loading or signed out.
///
/// A convenience for screens that only need the user and have already handled
/// loading elsewhere (everything behind the auth gate is in that position).
///
/// (In Riverpod 3 the nullable accessor is `.value`; the old `valueOrNull` is
/// gone, and `requireValue` is the one that throws when there is no data.)
final Provider<User?> currentUserProvider = Provider<User?>(
  (Ref ref) => ref.watch(authStateChangesProvider).value,
);
