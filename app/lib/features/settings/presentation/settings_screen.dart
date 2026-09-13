import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/application/auth_providers.dart';
import '../../notifications/presentation/reminder_settings_card.dart';

/// Account details and sign-out.
///
/// Unlike the other three tabs this one is **not** a placeholder: it is how
/// Milestone 0 proves itself. It reads the live Firebase user and can end the
/// session, which exercises the whole chain — repository → provider → router
/// redirect — in both directions.
///
/// It extends [ConsumerWidget] rather than [StatelessWidget]: that is the only
/// difference, and it grants the extra `ref` argument in [build] used to watch
/// providers.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `watch` (not `read`): if the user object changes, this screen rebuilds.
    final AsyncValue<User?> authState = ref.watch(authStateChangesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      // Every stream-backed screen handles all three states explicitly — the
      // project rule, enforced here by `AsyncValue.when` requiring all three
      // callbacks.
      body: authState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not read your account: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.statusCritical),
            ),
          ),
        ),
        data: (User? user) {
          if (user == null) {
            // The router's redirect should already have moved us to sign-in;
            // this is the belt-and-braces branch for the frame in between.
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _AccountCard(user: user),
              const SizedBox(height: 16),
              const ReminderSettingsCard(),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context, ref),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Zavithar Manager · Milestone 0',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: const Text('Sign out?'),
        content: const Text(
          'Your data stays in the cloud — you can sign back in at any time.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // No manual navigation afterwards: signing out makes `authStateChanges`
    // emit null, which wakes the router's redirect, which sends us to the login
    // screen. Navigation follows state rather than being commanded.
    await ref.read(authRepositoryProvider).signOut();
  }
}

/// Shows who is signed in, with the Google avatar when there is one.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final String? photoUrl = user.photoURL;
    final String initial = (user.displayName?.isNotEmpty ?? false)
        ? user.displayName![0].toUpperCase()
        : (user.email?.isNotEmpty ?? false)
        ? user.email![0].toUpperCase()
        : '?';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.brandPrimaryDark,
              foregroundImage: photoUrl == null ? null : NetworkImage(photoUrl),
              child: Text(
                initial,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    user.displayName ?? 'Signed in',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email ?? 'No email on this account',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
