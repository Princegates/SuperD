import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';

class DriversScreen extends ConsumerWidget {
  const DriversScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drivers = ref.watch(driversListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Drivers')),
      body: AsyncValueView(
        value: drivers,
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No drivers yet. Ask them to create an account from the app '
                  '– they will appear here automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final driver = items[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      driver.displayName.isNotEmpty
                          ? driver.displayName[0].toUpperCase()
                          : '?',
                    ),
                  ),
                  title: Text(driver.displayName),
                  subtitle: Text(driver.phone?.isNotEmpty == true
                      ? '${driver.email} · ${driver.phone}'
                      : driver.email),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
