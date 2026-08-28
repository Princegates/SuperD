import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../models/driver_vehicle_type.dart';
import '../../../models/profile.dart';
import '../../../models/user_role.dart';
import '../../../shared/utils/audit_log.dart';
import '../providers/admin_providers.dart';

/// Add-or-edit form for a driver's or dispatcher's roster details. In add
/// mode this also creates the login (via an Edge Function, since that needs
/// the service-role key). In edit mode it's a plain profile update - except
/// email, which is tied to the login itself: only a super admin editing an
/// existing account can fix it, via a separate Edge Function.
class StaffFormScreen extends ConsumerStatefulWidget {
  const StaffFormScreen({
    super.key,
    this.existing,
    this.roleToCreate = UserRole.driver,
  });

  final Profile? existing;

  /// Which role to create when [existing] is null. Ignored when editing -
  /// the role shown is then whatever [existing] already is (roles are
  /// changed from the Team screen's role control, not this form).
  final UserRole roleToCreate;

  bool get isEditing => existing != null;

  UserRole get role => existing?.role ?? roleToCreate;

  @override
  ConsumerState<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends ConsumerState<StaffFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.fullName,
  );
  late final _emailController = TextEditingController(
    text: widget.existing?.email,
  );
  late final _phoneController = TextEditingController(
    text: widget.existing?.phone,
  );
  late final _ghanaCardController = TextEditingController(
    text: widget.existing?.ghanaCardNumber,
  );
  late final _vehicleController = TextEditingController(
    text: widget.existing?.vehicleNumber,
  );
  late final _residentialAddressController = TextEditingController(
    text: widget.existing?.residentialAddress,
  );
  late final _dobController = TextEditingController(
    text: _formatDate(widget.existing?.dateOfBirth),
  );
  late DateTime? _dateOfBirth = widget.existing?.dateOfBirth;
  late String? _zoneId = widget.existing?.zoneId;
  late DriverVehicleType? _vehicleType = widget.existing?.vehicleType;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isDriver => widget.role == UserRole.driver;

  bool get _callerIsSuperAdmin =>
      ref.read(currentProfileProvider).valueOrNull?.role == UserRole.superAdmin;

  static String _formatDate(DateTime? date) =>
      date == null ? '' : DateFormat('dd MMM yyyy').format(date);

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dobController.text = _formatDate(picked);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ghanaCardController.dispose();
    _vehicleController.dispose();
    _residentialAddressController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(profileRepositoryProvider);
      if (widget.isEditing) {
        await repo.updateDriverDetails(
          userId: widget.existing!.id,
          fullName: _nameController.text.trim(),
          phone: _emptyToNull(_phoneController.text),
          ghanaCardNumber: _isDriver
              ? _emptyToNull(_ghanaCardController.text)
              : null,
          vehicleNumber: _isDriver
              ? _emptyToNull(_vehicleController.text)
              : null,
          vehicleType: _isDriver ? _vehicleType : null,
          dateOfBirth: _isDriver ? null : _dateOfBirth,
          residentialAddress: _emptyToNull(_residentialAddressController.text),
          zoneId: _isDriver ? _zoneId : null,
        );

        final newEmail = _emailController.text.trim();
        if (_callerIsSuperAdmin && newEmail != widget.existing!.email) {
          await repo.updateEmail(
            userId: widget.existing!.id,
            newEmail: newEmail,
          );
        }

        ref
          ..invalidate(allProfilesProvider)
          ..invalidate(driversListProvider);
        if (mounted) context.pop();
      } else {
        final result = _isDriver
            ? await repo.createDriver(
                email: _emailController.text.trim(),
                fullName: _nameController.text.trim(),
                phone: _emptyToNull(_phoneController.text),
                ghanaCardNumber: _emptyToNull(_ghanaCardController.text),
                vehicleNumber: _emptyToNull(_vehicleController.text),
                vehicleType: _vehicleType,
                residentialAddress: _emptyToNull(
                  _residentialAddressController.text,
                ),
              )
            : await repo.createDispatcher(
                email: _emailController.text.trim(),
                fullName: _nameController.text.trim(),
                phone: _phoneController.text.trim(),
                dateOfBirth: _dateOfBirth!,
                residentialAddress: _residentialAddressController.text.trim(),
              );
        await logAuditEvent(
          ref.read(supabaseClientProvider),
          action: 'staff_created',
          entityType: 'profile',
          summary:
              'Added ${widget.role.label.toLowerCase()} '
              '${_nameController.text.trim()}',
        );
        ref
          ..invalidate(allProfilesProvider)
          ..invalidate(driversListProvider);
        if (mounted) {
          await _showAccountCreatedDialog(
            email: _emailController.text.trim(),
            tempPassword: result.tempPassword,
            emailSent: result.emailSent,
          );
        }
        if (mounted) context.pop();
      }
    } on StaffManagementException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(
        () => _errorMessage =
            'Could not save this ${widget.role.label.toLowerCase()}. '
            'Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _emptyToNull(String value) =>
      value.trim().isEmpty ? null : value.trim();

  Future<void> _showAccountCreatedDialog({
    required String email,
    required String tempPassword,
    required bool emailSent,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('${widget.role.label} account created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              emailSent
                  ? "We've emailed $email their sign-in details. They'll be "
                        'asked to set their own password on first sign-in. '
                        "If the email doesn't arrive, here's a fallback:"
                  : "Couldn't email $email automatically - share this "
                        'one-time password with them directly. They\'ll be '
                        'asked to set their own password on first sign-in.',
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      tempPassword,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: tempPassword));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = widget.role.label.toLowerCase();
    final callerIsSuperAdmin =
        ref.watch(currentProfileProvider).valueOrNull?.role ==
        UserRole.superAdmin;
    final emailEditable = !widget.isEditing || callerIsSuperAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit $roleLabel' : 'Add $roleLabel'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  enabled: emailEditable,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    helperText: !widget.isEditing
                        ? null
                        : emailEditable
                        ? 'Changes their sign-in email immediately'
                        : "Only a super admin can change this",
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
                    labelText: 'Telephone number',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (!_isDriver) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _dobController,
                    readOnly: true,
                    onTap: _pickDateOfBirth,
                    decoration: const InputDecoration(
                      labelText: 'Date of birth',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _residentialAddressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Residential address',
                  ),
                  validator: _isDriver
                      ? null
                      : (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (_isDriver) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _ghanaCardController,
                    decoration: const InputDecoration(
                      labelText: 'Ghana card number',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _vehicleController,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle number',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<DriverVehicleType?>(
                    initialValue: _vehicleType,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle type',
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
                    onChanged: (value) => setState(() => _vehicleType = value),
                  ),
                  if (widget.isEditing) ...[
                    const SizedBox(height: 14),
                    Consumer(
                      builder: (context, ref, _) {
                        final zones = ref.watch(zonesProvider).valueOrNull;
                        return DropdownButtonFormField<String?>(
                          initialValue: _zoneId,
                          decoration: const InputDecoration(
                            labelText: 'Zone',
                            helperText:
                                'Groups this driver for assignment '
                                'suggestions and pricing',
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No zone'),
                            ),
                            for (final zone in zones ?? [])
                              DropdownMenuItem<String?>(
                                value: zone.id,
                                child: Text(zone.name),
                              ),
                          ],
                          onChanged: (value) => setState(() => _zoneId = value),
                        );
                      },
                    ),
                  ],
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppTheme.danger),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
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
                      : Text(
                          widget.isEditing ? 'Save changes' : 'Add $roleLabel',
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
