import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/categories/presentation/categories_screen.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/finance/presentation/finance_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/startup/presentation/startup_screen.dart';
import '../../features/todos/presentation/todos_screen.dart';

/// Every navigable location in the app, in one place.
///
/// Using constants instead of scattering `'/finance'` string literals means a
/// renamed route is a compile error rather than a silently dead link.
abstract final class AppRoutes {
  /// Shown only while Firebase restores a saved session at cold start.
  static const String startup = '/startup';
  static const String signIn = '/sign-in';
  static const String dashboard = '/';
  static const String finance = '/finance';
  static const String todos = '/todos';
  static const String settings = '/settings';

  /// A child of [settings], so it pushes over the settings tab and keeps the
  /// bottom navigation bar rather than covering it.
  static const String categories = 'categories';
}

/// Builds the app's [GoRouter], including the auth gate.
///
/// Why the gate lives here and not in a wrapper widget: a widget that returns
/// either the login screen or the app cannot change the URL, so deep links stop
/// making sense — and Milestone 3 needs them, because tapping a reminder
/// notification has to open one specific todo. A `redirect` keeps routing and
/// permission in the same system: the location is always real, and an
/// unauthenticated attempt to reach it is rewritten to `/sign-in`.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  // GoRouter re-runs `redirect` when the Listenable it was given notifies. The
  // auth state is a Riverpod stream, not a Listenable, so this small
  // ValueNotifier adapts one to the other: `ref.listen` pushes each new
  // AsyncValue into it, and every push wakes the router up.
  final ValueNotifier<AsyncValue<User?>> authState =
      ValueNotifier<AsyncValue<User?>>(const AsyncValue<User?>.loading());

  ref.listen<AsyncValue<User?>>(
    authStateChangesProvider,
    (AsyncValue<User?>? previous, AsyncValue<User?> next) =>
        authState.value = next,
    fireImmediately: true,
  );
  ref.onDispose(authState.dispose);

  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    debugLogDiagnostics: true,
    refreshListenable: authState,
    redirect: (BuildContext context, GoRouterState state) {
      final AsyncValue<User?> auth = authState.value;
      final String location = state.matchedLocation;

      // Still restoring the session: hold on the startup screen rather than
      // flashing the login screen at a user who is in fact signed in.
      if (auth.isLoading) {
        return location == AppRoutes.startup ? null : AppRoutes.startup;
      }

      final bool signedIn = auth.value != null;

      // Signed out (this also covers a stream error — `value` is null there,
      // and the login screen surfaces the error itself).
      if (!signedIn) {
        return location == AppRoutes.signIn ? null : AppRoutes.signIn;
      }

      // Signed in but sitting on a pre-auth screen: move on into the app.
      if (location == AppRoutes.signIn || location == AppRoutes.startup) {
        return AppRoutes.dashboard;
      }

      // Signed in and going somewhere real — leave it alone.
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.startup,
        builder: (BuildContext context, GoRouterState state) =>
            const StartupScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (BuildContext context, GoRouterState state) =>
            const LoginScreen(),
      ),

      // A StatefulShellRoute wraps several parallel navigation "branches" in
      // one persistent shell. Each branch keeps its own navigation stack and
      // its own scroll position, so switching tabs and coming back lands you
      // where you left — which a plain IndexedStack of screens would not do.
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) => AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (BuildContext context, GoRouterState state) =>
                    const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.finance,
                builder: (BuildContext context, GoRouterState state) =>
                    const FinanceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.todos,
                builder: (BuildContext context, GoRouterState state) =>
                    const TodosScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                builder: (BuildContext context, GoRouterState state) =>
                    const SettingsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: AppRoutes.categories,
                    builder: (BuildContext context, GoRouterState state) =>
                        const CategoriesScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
