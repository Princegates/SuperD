import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_role.dart';
import '../../../shared/widgets/fade_slide_in.dart';
import '../../../shared/widgets/glow_orbs_background.dart';
import '../../../shared/widgets/shake_x.dart';

/// Labels shown on the login tabs - cosmetic only, the real role always
/// comes from the database. No "Admin" tab: a super admin still signs in
/// fine picking either tab, this just keeps the picker to the two roles
/// someone would actually choose between when signing in.
const _loginTabLabels = {
  UserRole.driver: 'Driver',
  UserRole.dispatcher: 'Dispatcher',
};

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AnimationController _ringController;

  bool _isSubmitting = false;
  String? _errorMessage;
  UserRole _selectedTab = UserRole.driver;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  Widget _energyRing(double angle, Color scaffoldBackground) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              AppTheme.accent.withValues(alpha: 0),
              AppTheme.accent.withValues(alpha: 0.55),
              AppTheme.accent.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.15, 0.3],
          ),
        ),
        child: Center(
          child: Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scaffoldBackground,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      // go_router redirect handles navigation once the auth state updates.
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not sign in. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffoldBackground = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GlowOrbsBackground(
              colors: [
                AppTheme.primary,
                AppTheme.accent,
                AppTheme.primaryLight,
              ],
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: FadeSlideIn(
                    child: ShakeX(
                      trigger: _errorMessage,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: SizedBox(
                                width: 92,
                                height: 92,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    AnimatedBuilder(
                                      animation: _ringController,
                                      builder: (context, _) => _energyRing(
                                        _ringController.value * 2 * math.pi,
                                        scaffoldBackground,
                                      ),
                                    ),
                                    Image.asset(
                                      'assets/icon/icon.png',
                                      height: 68,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Welcome',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sign in to SuperD as a ${_loginTabLabels[_selectedTab]}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 20),
                            SegmentedButton<UserRole>(
                              segments: [
                                for (final entry in _loginTabLabels.entries)
                                  ButtonSegment(
                                    value: entry.key,
                                    label: Text(entry.value),
                                  ),
                              ],
                              selected: {_selectedTab},
                              onSelectionChanged: (selection) => setState(
                                () => _selectedTab = selection.first,
                              ),
                              style: SegmentedButton.styleFrom(
                                selectedBackgroundColor: AppTheme.primary,
                                selectedForegroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              validator: (value) =>
                                  (value == null || !value.contains('@'))
                                  ? 'Enter a valid email'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              autofillHints: const [AutofillHints.password],
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (value) =>
                                  (value == null || value.length < 6)
                                  ? 'Password must be at least 6 characters'
                                  : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    context.push('/forgot-password'),
                                child: const Text('Forgot password?'),
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _errorMessage!,
                                style: const TextStyle(color: AppTheme.danger),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _isSubmitting ? null : _submit,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Sign in'),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () => context.go('/signup'),
                              child: const Text('Create account'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
