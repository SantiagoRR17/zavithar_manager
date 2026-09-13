import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/auth_providers.dart';
import '../data/auth_repository.dart';

/// Sign in, or create the account the first time.
///
/// Two paths, per the PRD: **Google** (FR-1, primary) and **email/password**
/// (FR-2, fallback). The Google button only appears where the plugin actually
/// works — Android — because `google_sign_in` has no Windows implementation.
/// On Windows the email/password form is the whole screen, which is exactly
/// what FR-2 exists for.
///
/// This is a [ConsumerStatefulWidget] because it owns genuinely local, throwaway
/// state — what is typed in the fields, whether a request is in flight, the last
/// error. None of that belongs in a provider: no other screen needs it, and it
/// should vanish when the screen does.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isBusy = false;
  bool _isRegistering = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Google's SDK needs one-time initialisation before `authenticate()` can be
    // called. Doing it here means it is already done by the time a thumb
    // reaches the button.
    unawaitedInit();
  }

  void unawaitedInit() {
    ref.read(authRepositoryProvider).initializeGoogleSignIn().catchError((
      Object error,
    ) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Google sign-in unavailable: $error');
    });
  }

  @override
  void dispose() {
    // Controllers hold native resources and listeners; not disposing them leaks.
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Runs an auth action with the shared busy/error handling around it.
  ///
  /// Every path through this screen has the same shape — clear the error, show
  /// a spinner, do the thing, translate a failure into a message — so it lives
  /// in one place rather than being repeated in three callbacks.
  ///
  /// Note there is no "on success, navigate" step. Success makes Firebase emit
  /// a new auth state, the router notices, and the redirect moves us. The
  /// widget may well be gone by then, which is why every `setState` below is
  /// guarded by `mounted`.
  Future<void> _run(Future<void> Function() action) async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await action();
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      // Backing out of the account picker is a normal thing to do, not an
      // error worth shouting about.
      setState(() => _errorMessage = failure.wasCancelled
          ? null
          : failure.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _signInWithGoogle() =>
      _run(() => ref.read(authRepositoryProvider).signInWithGoogle());

  Future<void> _submitEmailForm() {
    // `validate()` runs every field's validator and paints the error text.
    if (!(_formKey.currentState?.validate() ?? false)) return Future<void>.value();

    final AuthRepository repository = ref.read(authRepositoryProvider);
    final String email = _emailController.text;
    final String password = _passwordController.text;

    return _run(
      () => _isRegistering
          ? repository.registerWithEmail(email: email, password: password)
          : repository.signInWithEmail(email: email, password: password),
    );
  }

  Future<void> _sendPasswordReset() {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(
        () => _errorMessage = 'Enter your email address first, then tap reset.',
      );
      return Future<void>.value();
    }
    return _run(() async {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email.')),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showGoogle = ref
        .read(authRepositoryProvider)
        .supportsGoogleSignIn;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const _Wordmark(),
                    const SizedBox(height: 40),
                    Text(
                      _isRegistering ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),

                    if (showGoogle) ...<Widget>[
                      OutlinedButton.icon(
                        onPressed: _isBusy ? null : _signInWithGoogle,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('Continue with Google'),
                      ),
                      const SizedBox(height: 20),
                      const _OrDivider(),
                      const SizedBox(height: 20),
                    ],

                    TextFormField(
                      controller: _emailController,
                      enabled: !_isBusy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const <String>[AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (String? value) {
                        final String email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Enter your email address.';
                        // Deliberately loose: the real check is whether Firebase
                        // accepts it. A strict regex mostly rejects valid
                        // addresses.
                        if (!email.contains('@') || !email.contains('.')) {
                          return 'That does not look like an email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isBusy,
                      obscureText: true,
                      autofillHints: <String>[
                        _isRegistering
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submitEmailForm(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (String? value) {
                        final String password = value ?? '';
                        if (password.isEmpty) return 'Enter your password.';
                        // Firebase's own minimum. Enforced here too so the user
                        // finds out before a network round trip.
                        if (_isRegistering && password.length < 6) {
                          return 'Use at least 6 characters.';
                        }
                        return null;
                      },
                    ),

                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: _errorMessage!),
                    ],

                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isBusy ? null : _submitEmailForm,
                      child: _isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.textPrimary,
                              ),
                            )
                          : Text(_isRegistering ? 'Create account' : 'Sign in'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isBusy
                          ? null
                          : () => setState(() {
                              _isRegistering = !_isRegistering;
                              _errorMessage = null;
                            }),
                      child: Text(
                        _isRegistering
                            ? 'I already have an account'
                            : 'Create an account instead',
                      ),
                    ),
                    if (!_isRegistering)
                      TextButton(
                        onPressed: _isBusy ? null : _sendPasswordReset,
                        child: const Text('Forgot your password?'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Errors are shown inline with an icon, never colour alone — the same rule the
/// status palette follows.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.statusCritical),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            color: AppColors.statusCritical,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        Expanded(child: Divider()),
      ],
    );
  }
}

/// Plain text branding — the logo mark is still undecided and was explicitly
/// not allowed to block development.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        Text(
          'ZAVITHAR',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            letterSpacing: 6,
            fontSize: 24,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'MANAGER',
          style: TextStyle(
            color: AppColors.brandPrimaryLight,
            fontWeight: FontWeight.w500,
            letterSpacing: 8,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
