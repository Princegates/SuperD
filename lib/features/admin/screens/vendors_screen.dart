import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/vendor_link.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';

/// Dispatcher/super-admin view of every registered vendor, with a copyable
/// link for each one and a way to add the fixed list of zones vendors and
/// drivers get assigned to.
class VendorsScreen extends ConsumerWidget {
  const VendorsScreen({super.key});

  Future<void> _manageZones(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zones'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final zones = ref.watch(zonesProvider).valueOrNull ?? [];
                  if (zones.isEmpty) {
                    return const Text('No zones yet.');
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final zone in zones) Chip(label: Text(zone.name)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'New zone name',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      final name = controller.text.trim();
                      if (name.isEmpty) return;
                      await ref.read(vendorRepositoryProvider).createZone(name);
                      controller.clear();
                      ref.invalidate(zonesProvider);
                    },
                  ),
                ],
              ),
            ],
          ),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsState = ref.watch(vendorsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendors'),
        actions: [
          IconButton(
            tooltip: 'Manage zones',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => _manageZones(context, ref),
          ),
        ],
      ),
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
              return ListView(
                children: [
                  SizedBox(
                    height: 400,
                    child: Center(
                      child: Text(
                        'No vendors yet. Tap "Add vendor" to register one, or '
                        'share the self-signup link: ${Uri.base.origin}'
                        '/vendor-signup',
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

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
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
              ],
            ),
            const SizedBox(height: 4),
            Text(vendor.phone, style: const TextStyle(color: Colors.black54)),
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
