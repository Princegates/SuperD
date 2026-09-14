import 'package:flutter/foundation.dart' show Uint8List, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../models/driver_vehicle_type.dart';
import '../../../models/profile.dart';
import '../../../models/staff_permission.dart';
import '../../../models/user_role.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/utils/ghana_phone.dart';
import '../../../shared/utils/rider_photo.dart';
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
  late final _licenseNumberController = TextEditingController(
    text: widget.existing?.drivingLicenseNumber,
  );
  late final _licenseExpiryController = TextEditingController(
    text: _formatDate(widget.existing?.drivingLicenseExpiry),
  );
  late final _insuranceNumberController = TextEditingController(
    text: widget.existing?.vehicleInsuranceNumber,
  );
  late final _insuranceExpiryController = TextEditingController(
    text: _formatDate(widget.existing?.vehicleInsuranceExpiry),
  );
  late DateTime? _dateOfBirth = widget.existing?.dateOfBirth;
  late DateTime? _licenseExpiry = widget.existing?.drivingLicenseExpiry;
  late DateTime? _insuranceExpiry = widget.existing?.vehicleInsuranceExpiry;
  late String? _zoneId = widget.existing?.zoneId;
  late DriverVehicleType? _vehicleType = widget.existing?.vehicleType;

  /// A newly chosen photo, held in memory until the account exists (on
  /// create) or until save (on edit). Null means "leave whatever is there".
  Uint8List? _photo;
  String? _photoError;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isDriver => widget.role == UserRole.driver;

  /// A link to the photo already on file, so an editing admin can see what
  /// they would be replacing. Lazy and read once - the form is not a live
  /// view of the roster. Short-circuits before touching the repository
  /// when there is nothing to fetch, which is every "add" form.
  late final Future<String?> _existingPhotoUrl = _loadExistingPhoto();

  Future<String?> _loadExistingPhoto() async {
    final path = widget.existing?.avatarPath;
    if (path == null) return null;
    return ref.read(profileRepositoryProvider).riderPhotoUrl(path);
  }

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

  Future<void> _pickExpiry(
    DateTime? current,
    TextEditingController controller,
    ValueChanged<DateTime> onPicked,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (current != null && current.isAfter(now))
          ? current
          : now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) {
      setState(() {
        onPicked(picked);
        controller.text = _formatDate(picked);
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
    _licenseNumberController.dispose();
    _licenseExpiryController.dispose();
    _insuranceNumberController.dispose();
    _insuranceExpiryController.dispose();
    super.dispose();
  }

  /// Where an admin's photo comes from depends on where they are sitting.
  /// On web this is a back-office browser with no useful camera, so go
  /// straight to the file dialog; on a phone, offer both - a dispatcher
  /// standing in front of a new rider can just photograph them.
  Future<void> _choosePhoto() async {
    if (kIsWeb) {
      await _pickPhoto(ImageSource.gallery);
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from files'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickPhoto(source);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // A first pass at the device's own encoder so we are not decoding a
      // full-resolution frame. RiderPhoto does the real work of getting
      // under the 200 KB cap.
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 90,
    );
    if (picked == null) return;
    final shrunk = RiderPhoto.compress(await picked.readAsBytes());
    if (!mounted) return;
    setState(() {
      if (shrunk == null) {
        _photoError = "That file isn't an image we can read. Try a JPEG "
            'or PNG.';
      } else {
        _photo = shrunk;
        _photoError = null;
      }
    });
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
        // Photo first, deliberately. Replacing a rider's photo is the one
        // edit here the database would refuse from anyone but staff (see
        // `enforce_profile_role_change` in 0091_rider_photo.sql), so if it
        // is going to fail, fail before the rest of the form is written
        // and the error message is still true.
        if (_isDriver && _photo != null) {
          await repo.uploadRiderPhoto(
            userId: widget.existing!.id,
            bytes: _photo!,
          );
          await logAuditEvent(
            ref.read(supabaseClientProvider),
            action: 'rider_photo_replaced',
            entityType: 'profile',
            entityId: widget.existing!.id,
            summary:
                'Replaced the photo on file for '
                '${_nameController.text.trim()}',
          );
        }
        await repo.updateDriverDetails(
          userId: widget.existing!.id,
          fullName: _nameController.text.trim(),
          phone: GhanaPhone.normalize(_phoneController.text.trim()),
          ghanaCardNumber: _isDriver
              ? _emptyToNull(_ghanaCardController.text)
              : null,
          vehicleNumber: _isDriver
              ? _emptyToNull(_vehicleController.text)
              : null,
          vehicleType: _isDriver ? _vehicleType : null,
          dateOfBirth: _dateOfBirth,
          residentialAddress: _emptyToNull(_residentialAddressController.text),
          zoneId: _isDriver ? _zoneId : null,
          drivingLicenseNumber: _isDriver
              ? _emptyToNull(_licenseNumberController.text)
              : null,
          drivingLicenseExpiry: _isDriver ? _licenseExpiry : null,
          vehicleInsuranceNumber: _isDriver
              ? _emptyToNull(_insuranceNumberController.text)
              : null,
          vehicleInsuranceExpiry: _isDriver ? _insuranceExpiry : null,
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
        final result = switch (widget.role) {
          UserRole.driver => await repo.createDriver(
            email: _emailController.text.trim(),
            fullName: _nameController.text.trim(),
            phone: GhanaPhone.normalize(_phoneController.text.trim()),
            ghanaCardNumber: _emptyToNull(_ghanaCardController.text),
            vehicleNumber: _emptyToNull(_vehicleController.text),
            vehicleType: _vehicleType,
            residentialAddress: _emptyToNull(
              _residentialAddressController.text,
            ),
            dateOfBirth: _dateOfBirth,
            drivingLicenseNumber: _emptyToNull(
              _licenseNumberController.text,
            ),
            drivingLicenseExpiry: _licenseExpiry,
            vehicleInsuranceNumber: _emptyToNull(
              _insuranceNumberController.text,
            ),
            vehicleInsuranceExpiry: _insuranceExpiry,
          ),
          UserRole.auditor => await repo.createAuditor(
            email: _emailController.text.trim(),
            fullName: _nameController.text.trim(),
            phone: GhanaPhone.normalize(_phoneController.text.trim())!,
            dateOfBirth: _dateOfBirth!,
            residentialAddress: _residentialAddressController.text.trim(),
          ),
          UserRole.dispatcher || UserRole.superAdmin => await repo
              .createDispatcher(
                email: _emailController.text.trim(),
                fullName: _nameController.text.trim(),
                phone: GhanaPhone.normalize(_phoneController.text.trim())!,
                dateOfBirth: _dateOfBirth!,
                residentialAddress: _residentialAddressController.text.trim(),
              ),
        };
        await logAuditEvent(
          ref.read(supabaseClientProvider),
          action: 'staff_created',
          entityType: 'profile',
          entityId: result.userId,
          summary:
              'Added ${widget.role.label.toLowerCase()} '
              '${_nameController.text.trim()}',
        );
        // Non-fatal on purpose: the account is already created and the
        // temporary password already emailed. Failing the whole flow here
        // would leave an admin thinking they have to start over, when all
        // that is missing is a picture they can add by editing the rider.
        var photoAttached = true;
        if (_isDriver && _photo != null) {
          final userId = result.userId;
          if (userId == null) {
            // No id came back, so there is nothing to attach the photo to.
            // Say so rather than let the admin assume it went up.
            photoAttached = false;
          } else {
            try {
              await repo.uploadRiderPhoto(userId: userId, bytes: _photo!);
            } catch (_) {
              photoAttached = false;
            }
          }
        }
        ref
          ..invalidate(allProfilesProvider)
          ..invalidate(driversListProvider);
        if (mounted) {
          await _showAccountCreatedDialog(
            email: _emailController.text.trim(),
            tempPassword: result.tempPassword,
            emailSent: result.emailSent,
            photoAttached: photoAttached,
          );
        }
        if (mounted) context.pop();
      }
    } on StaffManagementException catch (e) {
      setState(() => _errorMessage = e.message);
    } on StorageException catch (_) {
      setState(
        () => _errorMessage =
            "Couldn't upload the photo, so nothing was saved. Check the "
            'connection and try again.',
      );
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
    required bool photoAttached,
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
            if (!photoAttached) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The account is set up, but the photo did not upload. '
                      'Open this rider and try again - nothing else is '
                      'affected.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
                if (_isDriver) ...[
                  FutureBuilder<String?>(
                    future: _existingPhotoUrl,
                    builder: (context, snapshot) => _RiderPhotoField(
                      pending: _photo,
                      existingUrl: snapshot.data,
                      onTap: _isSubmitting ? null : _choosePhoto,
                    ),
                  ),
                  if (_photoError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _photoError!,
                      style: const TextStyle(
                        color: AppTheme.danger,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                ],
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
                  validator: GhanaPhone.validator(),
                ),
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
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                        child: Text('Select one'),
                      ),
                      for (final type in DriverVehicleType.values)
                        DropdownMenuItem<DriverVehicleType?>(
                          value: type,
                          child: Text(type.label),
                        ),
                    ],
                    onChanged: (value) => setState(() => _vehicleType = value),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _licenseNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Driving licence number',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _licenseExpiryController,
                    readOnly: true,
                    onTap: () => _pickExpiry(
                      _licenseExpiry,
                      _licenseExpiryController,
                      (date) => _licenseExpiry = date,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Driving licence expiry',
                      helperText: 'Must still be valid (not expired)',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _insuranceNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle insurance policy number',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _insuranceExpiryController,
                    readOnly: true,
                    onTap: () => _pickExpiry(
                      _insuranceExpiry,
                      _insuranceExpiryController,
                      (date) => _insuranceExpiry = date,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Vehicle insurance expiry',
                      helperText: 'Must still be valid (not expired)',
                      suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
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
                if (widget.isEditing &&
                    callerIsSuperAdmin &&
                    (widget.role == UserRole.dispatcher ||
                        widget.role == UserRole.auditor)) ...[
                  const SizedBox(height: 20),
                  _PermissionOverridesSection(person: widget.existing!),
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

/// Lets a super admin fine-tune one dispatcher/auditor's permissions
/// beyond their role's normal defaults - a key present in
/// [Profile.permissionOverrides] wins outright; "Default" clears it back
/// to whatever the role normally gets. Applies immediately on selection
/// (a plain profile update, not part of the surrounding form's submit),
/// same as [RoleControl] on the Team screen changing a role.
class _PermissionOverridesSection extends ConsumerWidget {
  const _PermissionOverridesSection({required this.person});

  final Profile person;

  Future<void> _setOverride(
    BuildContext context,
    WidgetRef ref,
    StaffPermission permission,
    bool? allowed,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).setPermissionOverride(
        userId: person.id,
        permission: permission,
        allowed: allowed,
      );
      ref.invalidate(allProfilesProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update that permission')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-reads the live profile rather than trusting [person] (which is
    // whatever was passed in when this screen opened) so a toggle here
    // reflects immediately, and survives this section being rebuilt after
    // another toggle.
    final live =
        ref.watch(allProfilesProvider).valueOrNull?.firstWhere(
              (p) => p.id == person.id,
              orElse: () => person,
            ) ??
        person;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Permissions',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              "Overrides ${live.role.label.toLowerCase()}s' usual "
              "permissions for ${live.displayName} specifically.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            for (final permission in StaffPermission.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(permission.label)),
                    _PermissionChip(
                      allowed: live.permissionOverrides[permission.wireValue],
                      roleDefault: live.roleDefaultPermission(permission),
                      onSelected: (allowed) =>
                          _setOverride(context, ref, permission, allowed),
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

class _PermissionChip extends StatelessWidget {
  const _PermissionChip({
    required this.allowed,
    required this.roleDefault,
    required this.onSelected,
  });

  /// The explicit override, if any - null means "no override, using the
  /// role default".
  final bool? allowed;
  final bool roleDefault;
  final ValueChanged<bool?> onSelected;

  @override
  Widget build(BuildContext context) {
    final color = (allowed ?? roleDefault) ? AppTheme.success : AppTheme.danger;
    final label = allowed == null
        ? 'Default (${roleDefault ? 'allowed' : 'denied'})'
        : (allowed! ? 'Always allowed' : 'Always denied');
    // PopupMenuButton can't tell "the user picked the null-valued item"
    // apart from "the user dismissed the menu without picking anything" -
    // both come back as a null result from showMenu() internally, and it
    // only calls onSelected for the former. Routing through this
    // non-nullable enum and translating back to bool? afterward sidesteps
    // that entirely, instead of silently dropping every tap on "Default".
    return PopupMenuButton<_OverrideChoice>(
      tooltip: 'Change this permission',
      onSelected: (choice) => onSelected(switch (choice) {
        _OverrideChoice.useDefault => null,
        _OverrideChoice.allow => true,
        _OverrideChoice.deny => false,
      }),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _OverrideChoice.useDefault,
          child: Text('Default (${roleDefault ? 'allowed' : 'denied'})'),
        ),
        const PopupMenuItem(
          value: _OverrideChoice.allow,
          child: Text('Always allow'),
        ),
        const PopupMenuItem(
          value: _OverrideChoice.deny,
          child: Text('Always deny'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: color),
          ],
        ),
      ),
    );
  }
}

enum _OverrideChoice { useDefault, allow, deny }

/// The rider's photo, as an admin sees it on this form.
///
/// Three states, and the wording has to separate them: nothing on file, a
/// picture just chosen but not yet saved, and one already stored that this
/// admin would be replacing. Staff are the only ones who can do that last
/// one - a rider's own photo locks the moment they are approved - so the
/// copy says as much rather than letting someone replace a face by
/// accident.
class _RiderPhotoField extends StatelessWidget {
  const _RiderPhotoField({
    required this.pending,
    required this.existingUrl,
    required this.onTap,
  });

  /// Chosen on this form, not yet uploaded.
  final Uint8List? pending;

  /// A signed link to what is already stored, if anything.
  final String? existingUrl;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasPending = pending != null;
    final hasExisting = existingUrl != null;
    final has = hasPending || hasExisting;

    final (title, subtitle) = switch ((hasPending, hasExisting)) {
      (true, true) => (
        'New photo chosen',
        'Replaces the one on file when you save.',
      ),
      (true, false) => ('Photo chosen', 'Tap to pick a different one.'),
      (false, true) => (
        'Photo on file',
        'Tap to replace it. A rider cannot change their own once they are '
            'approved, so replacements are recorded in the audit log.',
      ),
      (false, false) => (
        'Add a photo',
        'Optional. So dispatch and customers know who is coming - the '
            'rider can also add their own at first sign-in.',
      ),
    };

    return Row(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 86,
            height: 86,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primary.withValues(alpha: 0.08),
              border: Border.all(
                color: has ? AppTheme.primary : Colors.grey.shade300,
                width: has ? 2 : 1,
              ),
            ),
            child: hasPending
                ? Image.memory(pending!, fit: BoxFit.cover)
                : hasExisting
                ? Image.network(
                    existingUrl!,
                    fit: BoxFit.cover,
                    // A broken link is not worth an error box on a form -
                    // fall back to the same prompt as "no photo yet".
                    errorBuilder: (context, _, _) => _placeholder(),
                  )
                : _placeholder(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Icon(
    Icons.add_a_photo_outlined,
    color: Colors.grey.shade500,
    size: 26,
  );
}
