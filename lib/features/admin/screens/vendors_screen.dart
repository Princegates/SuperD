import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
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

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/vendors/new'),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Add vendor'),
      ),
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
                                  'the web build: /vendor-signup'
                            : 'No vendors yet. Tap "Add vendor" to register '
                                  'one, or share the self-signup link: '
                                  '$base/vendor-signup',
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
                  _VendorCard(vendor: vendors[index]),
            );
          },
        ),
      ),
    );
  }
}

class _VendorCard extends ConsumerWidget {
  const _VendorCard({required this.vendor});

  final Vendor vendor;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = vendorLink(vendor.code);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    vendor.vendorName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (!vendor.isActive)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Inactive',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
                if (vendor.zoneName != null)
                  Container(
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
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
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
                    color: vendor.isActive ? AppTheme.success : Colors.black38,
                  ),
                  onPressed: () => _toggleActive(ref, context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              vendor.email?.isNotEmpty == true
                  ? '${vendor.phone} · ${vendor.email}'
                  : vendor.phone,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      link,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy link',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    },
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
