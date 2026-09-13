import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Shown for the fraction of a second while Firebase restores a saved session.
///
/// Why it needs to exist: `FirebaseAuth.authStateChanges()` does not tell you
/// immediately whether someone is signed in — at cold start it is in the
/// `loading` state until the persisted token is read from disk. Without this
/// screen the router would treat "don't know yet" as "signed out" and flash the
/// login screen at an already-signed-in user on every launch.
class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'ZAVITHAR',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                fontSize: 18,
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
