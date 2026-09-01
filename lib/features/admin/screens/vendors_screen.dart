import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/vendor_repository.dart' show VendorLinkException;
import '../../../models/staff_permission.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/utils/vendor_link.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';

/// The "Vendors" section of the admin dashboard shell ([AdminShellScreen]) -
/// every registered vendor, with a copyable link for each one. Zones
/// themselves (the fixed list vendors and drivers pick from) are managed
/// from the super-admin Console's Zones section, not here - only a super
/// admin can actually create one (RLS on `zones`), so this screen no
/// longer offers an entry point that would fail for a dispatcher.
class VendorsScreen extends ConsumerWidget {
  const VendorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsState = ref.watch(vendorsProvider);
    final canManage =
        ref.watch(currentProfileProvider).valueOrNull?.hasPermission(
              StaffPermission.manageVendors,
            ) ??
        false;

    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/admin/vendors/new'),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Add vendor'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(vendorsProvider),
        child: AsyncValueView<List<Vendor>>(
          value: vendorsState,
          data: (vendors) {
            if (vendors.isEmpty) {
              final base = publicBaseUrl();
              return ListView(
                children: [
                  SizedBox(
                    height: 400,
                    child: Center(
                      child: Text(
                        base.isEmpty
                            ? 'No vendors yet. Tap "Add vendor" to register '
                                  'one, or share the self-signup link from '
                                  'the web build: /vendor'
                            : 'No vendors yet. Tap "Add vendor" to register '
                                  'one, or share the self-signup link: '
                                  '$base/vendor',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: vendors.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _VendorCard(vendor: vendors[index], canManage: canManage),
            );
          },
        ),
      ),
    );
  }
}

class _VendorCard extends ConsumerWidget {
  const _VendorCard({required this.vendor, required this.canManage});

  final Vendor vendor;

  /// The manage_vendors permission (see `StaffPermission`) - a super admin
  /// can revoke it from one specific dispatcher/auditor, hiding these
  /// action icons for them (the write itself is rejected server-side too,
  /// via RLS - this is just so the UI doesn't offer a doomed action).
  final bool canManage;

  Future<void> _toggleActive(WidgetRef ref, BuildContext context) async {
    try {
      final newActive = !vendor.isActive;
      await ref
          .read(vendorRepositoryProvider)
          .setVendorActive(vendor.id, newActive);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: newActive ? 'vendor_activated' : 'vendor_deactivated',
        entityType: 'vendor',
        entityId: vendor.id,
        summary:
            '${newActive ? 'Activated' : 'Deactivated'} vendor '
            '${vendor.vendorName}',
      );
      ref.invalidate(vendorsProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this vendor')),
        );
      }
    }
  }

  /// [channel] is `'sms'` or `'email'` - each has its own button below, so
  /// a dispatcher can resend over whichever one actually didn't arrive
  /// instead of always sending both.
  Future<void> _resendLink(
    BuildContext context,
    WidgetRef ref,
    String channel,
  ) async {
    try {
      await ref
          .read(vendorRepositoryProvider)
          .resendVendorLink(vendorId: vendor.id, channel: channel);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'vendor_link_resent',
        entityType: 'vendor',
        entityId: vendor.id,
        summary:
            'Resent link to vendor ${vendor.vendorName} via '
            '${channel == 'sms' ? 'SMS' : 'email'}',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link resent')),
        );
      }
    } on VendorLinkException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not resend the link')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete vendor?'),
        content: Text(
          'This permanently removes "${vendor.vendorName}" and their link. '
          "It can't be undone, and only works if they have no delivery "
          'history - deactivate instead if you just want to stop new '
          'requests.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(vendorRepositoryProvider).deleteVendor(vendor.id);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'vendor_deleted',
        entityType: 'vendor',
        entityId: vendor.id,
        summary: 'Deleted vendor ${vendor.vendorName}',
      );
      ref.invalidate(vendorsProvider);
    } on PostgrestException catch (e) {
      if (!context.mounted) return;
      final inUse = e.code == '23503';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inUse
                ? '"${vendor.vendorName}" has delivery history - '
                      'deactivate instead of deleting'
                : 'Could not delete this vendor',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = vendorLink(vendor.code);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cramming the name, both badges, and all four action icons
            // into one Row left almost no width for the name on a phone
            // screen - Flutter's Text falls back to wrapping one or two
            // characters per line rather than overflowing horizontally.
            // Splitting the badges onto the name's own row (still just an
            // Expanded, a real bounded width) and giving the actions a
            // separate Wrap underneath (so they can flow onto a second
            // line instead of stealing space from the text above) fixes
            // it the same way PersonCard already does for the identical
            // problem on Team/Drivers.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    vendor.vendorName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (!vendor.isActive)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (vendor.isPaymentPending
                                  ? AppTheme.warning
                                  : AppTheme.danger)
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      // A vendor still owing their one-time subscription
                      // fee (see 0074_vendor_subscriptions.sql) gets a
                      // more specific badge than a plain "Inactive" -
                      // this is a soft gate (the toggle below still
                      // activates them regardless of payment), so it's
                      // meant to explain *why* they're inactive, not just
                      // that they are.
                      vendor.isPaymentPending ? 'Payment pending' : 'Inactive',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: vendor.isPaymentPending
                            ? AppTheme.warning
                            : AppTheme.danger,
                      ),
                    ),
                  ),
                if (vendor.zoneName != null)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      vendor.zoneName!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            if (canManage) ...[
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Resend link via email',
                    icon: const Icon(
                      Icons.mark_email_unread_outlined,
                      size: 20,
                    ),
                    onPressed: () => _resendLink(context, ref, 'email'),
                  ),
                  IconButton(
                    tooltip: 'Resend link via SMS',
                    icon: const Icon(Icons.sms_outlined, size: 20),
                    onPressed: () => _resendLink(context, ref, 'sms'),
                  ),
                  IconButton(
                    tooltip: 'Edit vendor',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () =>
                        context.push('/admin/vendors/edit', extra: vendor),
                  ),
                  IconButton(
                    tooltip: vendor.isActive
                        ? 'Deactivate link'
                        : 'Activate link',
                    icon: Icon(
                      vendor.isActive
                          ? Icons.toggle_on
                          : Icons.toggle_off_outlined,
                      size: 26,
                      color: vendor.isActive
                          ? AppTheme.success
                          : Colors.black38,
                    ),
                    onPressed: () => _toggleActive(ref, context),
                  ),
                  IconButton(
                    tooltip: 'Delete vendor',
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: AppTheme.danger,
                    ),
                    onPressed: () => _delete(context, ref),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text(
              vendor.email?.isNotEmpty == true
                  ? '${vendor.phone} · ${vendor.email}'
                  : vendor.phone,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            _LinkRow(link: link),
            const SizedBox(height: 8),
            Text(
              "Private orders link (vendor only - never share with a customer):",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            _LinkRow(link: vendorOrdersLink(vendor.ordersCode)),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(link, style: const TextStyle(fontSize: 13)),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Link copied')));
            },
          ),
        ],
      ),
    );
  }
}
