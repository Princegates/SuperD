import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/special_delivery_request.dart';
import '../providers/admin_providers.dart';

/// A banner listing vendor-submitted special-delivery requests still
/// waiting on a dispatcher - see `0099_vendor_special_delivery_requests.sql`
/// and [SpecialDeliveryRequest]. Mirrors [ScheduledDeliveryBanner]'s
/// expand/collapse shape, but each row acts rather than just links: a
/// dispatcher either starts pricing it (into CreateDeliveryScreen, with the
/// vendor and customer details already filled in) or dismisses it outright.
class SpecialDeliveryRequestsBanner extends ConsumerStatefulWidget {
  const SpecialDeliveryRequestsBanner({super.key, required this.requests});

  final List<SpecialDeliveryRequest> requests;

  @override
  ConsumerState<SpecialDeliveryRequestsBanner> createState() =>
      _SpecialDeliveryRequestsBannerState();
}

class _SpecialDeliveryRequestsBannerState
    extends ConsumerState<SpecialDeliveryRequestsBanner> {
  bool _expanded = false;

  Future<void> _dismiss(SpecialDeliveryRequest request) async {
    await ref
        .read(vendorRepositoryProvider)
        .dismissSpecialDeliveryRequest(request.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dismissed ${request.customerName}\'s request')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requests.isEmpty) return const SizedBox.shrink();
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? const [];
    final vendorNames = {for (final v in vendors) v.id: v.vendorName};

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${widget.requests.length} special delivery '
                      '${widget.requests.length == 1 ? 'request' : 'requests'} '
                      'from vendors',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: [
                  for (final request in widget.requests)
                    _RequestRow(
                      request: request,
                      vendorName: vendorNames[request.vendorId] ?? 'A vendor',
                      onDismiss: () => _dismiss(request),
                    ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.vendorName,
    required this.onDismiss,
  });

  final SpecialDeliveryRequest request;
  final String vendorName;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$vendorName · ${request.customerName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  request.dropoffAddress,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
                Text(
                  DateFormat('d MMM, h:mm a').format(request.createdAt.toLocal()),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
          FilledButton(
            onPressed: () => context.push('/admin/new', extra: request),
            child: const Text('Price it'),
          ),
        ],
      ),
    );
  }
}
