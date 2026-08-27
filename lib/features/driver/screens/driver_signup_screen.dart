import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/driver_vehicle_type.dart';

/// Self-service signup for drivers only - reachable from the login screen's
/// Driver tab, native app only (the router keeps this route out of reach
/// on web, since that build is back-office only). A dispatcher account can
/// never be created this way; only a super admin or existing dispatcher
/// creating one from the Team screen can do that.
class DriverSignupScreen extends ConsumerStatefulWidget {
  const DriverSignupScreen({super.key});

  @override
  ConsumerState<DriverSignupScreen> createState() => _DriverSignupScreenState();
}

class _DriverSignupScreenState extends ConsumerState<DriverSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  DriverVehicleType? _vehicleType;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _checkEmail = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final response = await ref
          .read(authRepositoryProvider)
          .signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName: _nameController.text.trim(),
            phone: _emptyToNull(_phoneController.text),
            vehicleNumber: _emptyToNull(_vehicleController.text),
            vehicleType: _vehicleType,
          );
      // A session means the project has email confirmation off - the
      // router picks up the new session on its own and takes the driver
      // straight into the app. Otherwise, tell them to confirm first.
      if (mounted && response.session == null) {
        setState(() => _checkEmail = true);
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(
        () => _errorMessage =
            'Could not create your account. Please try '
            'again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _emptyToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create driver account')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _checkEmail
                  ? _CheckEmailCard(email: _emailController.text.trim())
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Sign up to start receiving deliveries assigned '
                            'to you.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Telephone number (optional)',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _vehicleController,
                            decoration: const InputDecoration(
                              labelText: 'Vehicle number (optional)',
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<DriverVehicleType?>(
                            initialValue: _vehicleType,
                            decoration: const InputDecoration(
                              labelText: 'Vehicle type (optional)',
                            ),
                            items: [
                              const DropdownMenuItem<DriverVehicleType?>(
                                value: null,
                                child: Text('Not set'),
                              ),
                              for (final type in DriverVehicleType.values)
                                DropdownMenuItem<DriverVehicleType?>(
                                  value: type,
                                  child: Text(type.label),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _vehicleType = value),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                            ),
                            validator: (v) => (v == null || v.length < 6)
                                ? 'Password must be at least 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Confirm password',
                            ),
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: AppTheme.danger),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 20),
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
                                : const Text('Create account'),
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

class _CheckEmailCard extends StatelessWidget {
  const _CheckEmailCard({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          color: AppTheme.success,
          size: 56,
        ),
        const SizedBox(height: 12),
        const Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        const SizedBox(height: 6),
        Text(
          "We've sent a confirmation link to $email. Tap it, then come back "
          'and sign in.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}
