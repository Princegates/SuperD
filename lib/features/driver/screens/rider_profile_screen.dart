import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/profile.dart';
import '../../../models/rider_rating.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/utils/rider_photo.dart';
import '../../../shared/widgets/rider_avatar.dart';
import '../providers/rider_profile_providers.dart';

/// What the app holds about a rider, shown to the rider.
///
/// Read-only, and that is the point rather than an omission. Who a rider
/// is - their name, their licence, the bike they ride - is what dispatch
/// matched to a job and what a customer was told to expect at the door.
/// Changes go through staff, who are then the ones on the audit trail for
/// it. The database enforces this (see `0091_rider_photo.sql`); this
/// screen just stops offering something that would be refused.
class RiderProfileScreen extends ConsumerStatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  ConsumerState<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends ConsumerState<RiderProfileScreen> {
  bool _uploading = false;

  /// Only reachable while the database would accept it - see
  /// `canStillSetPhoto`, which mirrors the rule in 0091. A rider who
  /// signed up before photos existed, or who is still waiting on
  /// approval, can set one here.
  Future<void> _addPhoto(String userId) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 90,
    );
    if (picked == null) return;

    final shrunk = RiderPhoto.compress(await picked.readAsBytes());
    if (!mounted) return;
    if (shrunk == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That photo couldn't be read.")),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .uploadRiderPhoto(userId: userId, bytes: shrunk);
      ref.invalidate(myPhotoUrlProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save your photo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final photoUrl = ref.watch(myPhotoUrlProvider).valueOrNull;
    final rating = ref.watch(myRatingProvider).valueOrNull;
    final supportPhone = ref
        .watch(appSettingsProvider)
        .valueOrNull
        ?.supportPhone;

    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: Column(
              children: [
                RiderAvatar(
                  name: profile.displayName,
                  photoUrl: photoUrl,
                  size: 116,
                ),
                const SizedBox(height: 14),
                Text(
                  profile.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!profile.isActive) ...[
                  const SizedBox(height: 6),
                  const _PendingChip(),
                ],
                if (profile.canStillSetPhoto) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _uploading ? null : () => _addPhoto(profile.id),
                    icon: _uploading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      profile.avatarPath == null
                          ? 'Add your photo'
                          : 'Retake photo',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
          _RatingCard(rating: rating),
          const SizedBox(height: 18),
          _DetailsCard(profile: profile),
          const SizedBox(height: 18),
          _ChangeRequestCard(supportPhone: supportPhone),
        ],
      ),
    );
  }
}

class _PendingChip extends StatelessWidget {
  const _PendingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Waiting for approval',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.warning,
        ),
      ),
    );
  }
}

/// The rider's own score. Their average, what it is drawn from, and the
/// spread - never the customers' written comments, which stay with
/// dispatch (see 0092).
class _RatingCard extends StatelessWidget {
  const _RatingCard({this.rating});

  final RiderRating? rating;

  @override
  Widget build(BuildContext context) {
    final r = rating;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My rating',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            if (r == null)
              const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (!r.hasRatings)
              Text(
                'No ratings yet. Customers can rate you after a delivery.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              )
            else ...[
              // The count sits under the score rather than beside it. On
              // a small phone the big number, "out of 5" and "from N
              // ratings" together are wider than the card, and a Spacer
              // between them cannot give back space that was never there.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    r.average!.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'out of 5',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                r.count == 1 ? 'from 1 rating' : 'from ${r.count} ratings',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 14),
              for (final star in [5, 4, 3, 2, 1])
                _StarRow(
                  star: star,
                  count: r.byStar[star] ?? 0,
                  total: r.count,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({
    required this.star,
    required this.count,
    required this.total,
  });

  final int star;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Text('$star', style: const TextStyle(fontSize: 12)),
          ),
          Icon(Icons.star_rounded, size: 14, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(AppTheme.accent),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    String? date(DateTime? d) =>
        d == null ? null : DateFormat('d MMM y').format(d);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My details',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            _Line(label: 'Phone', value: profile.phone),
            _Line(label: 'Email', value: profile.email),
            _Line(label: 'Ghana Card', value: profile.ghanaCardNumber),
            _Line(label: 'Date of birth', value: date(profile.dateOfBirth)),
            _Line(label: 'Address', value: profile.residentialAddress),
            const Divider(height: 26),
            _Line(label: 'Vehicle', value: profile.vehicleType?.label),
            _Line(label: 'Registration', value: profile.vehicleNumber),
            _Line(label: 'Licence', value: profile.drivingLicenseNumber),
            _Line(
              label: 'Licence expires',
              value: date(profile.drivingLicenseExpiry),
              // An expired licence is the rider's problem to fix before
              // it becomes a roadside problem, so it is called out here
              // rather than left as another grey line.
              warn:
                  profile.drivingLicenseExpiry != null &&
                  profile.drivingLicenseExpiry!.isBefore(DateTime.now()),
            ),
            _Line(label: 'Insurance', value: profile.vehicleInsuranceNumber),
            _Line(
              label: 'Insurance expires',
              value: date(profile.vehicleInsuranceExpiry),
              warn:
                  profile.vehicleInsuranceExpiry != null &&
                  profile.vehicleInsuranceExpiry!.isBefore(DateTime.now()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Changes go through staff. Rather than a disabled edit button, this says
/// so plainly and gives them the one action that actually works.
class _ChangeRequestCard extends StatelessWidget {
  const _ChangeRequestCard({this.supportPhone});

  final String? supportPhone;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.primary.withValues(alpha: 0.05),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                // Expanded, so the heading wraps inside the card instead
                // of running past its edge on a narrow screen.
                const Expanded(
                  child: Text(
                    'Something wrong here?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your details and your photo are fixed once your account is '
              'approved, so that the person dispatch sends is the person '
              'who turns up. Call the office and they will update it for '
              'you.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            if (supportPhone?.isNotEmpty == true) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => launchPhoneCall(supportPhone!),
                icon: const Icon(Icons.phone_outlined, size: 18),
                label: Text('Call $supportPhone'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, this.value, this.warn = false});

  final String label;
  final String? value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.isNotEmpty == true ? value! : 'Not on file',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: warn
                    ? AppTheme.warning
                    : (value?.isNotEmpty == true ? null : Colors.grey.shade400),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
