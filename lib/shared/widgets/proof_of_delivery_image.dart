import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_providers.dart';

/// A delivery's proof photo, fetched through a short-lived signed link.
///
/// The bucket went private in 0098 - these photos are taken at a
/// customer's door and show their address - so the value stored on the
/// delivery is a path, and a viewable link has to be minted per view.
/// That makes displaying one an async step where it used to be a plain
/// URL, which is the whole reason this widget exists rather than an
/// `Image.network` at each call site.
///
/// Fails quietly. A detail screen has a job to do whether or not one
/// photo loads, so a missing or unreadable file leaves a small note in
/// place of the image rather than an error box over the page.
class ProofOfDeliveryImage extends ConsumerWidget {
  const ProofOfDeliveryImage({
    super.key,
    required this.path,
    this.borderRadius = 16,
  });

  /// What is stored on the delivery row - a bucket path, or an absolute
  /// URL on rows written before 0098.
  final String path;

  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.read(deliveryRepositoryProvider).proofOfDeliveryUrl(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        }
        final url = snapshot.data;
        if (url == null) return const _Unavailable();
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, _, _) => const _Unavailable(),
          ),
        );
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.image_not_supported_outlined, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "This photo couldn't be loaded.",
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}
