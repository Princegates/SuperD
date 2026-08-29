import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/customer.dart';
import '../../../models/delivery.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/status_badge.dart';
import '../providers/console_providers.dart';

/// Customer-service lookup: name, email, phone, and last-known address for
/// every customer who's ever placed a delivery, kept current automatically
/// (see `0055_customer_directory.sql`), with their full delivery history
/// one tap away. Super-admin-only - not opened up to an auditor the way
/// every other Console section is, since customer contact details aren't
/// something an oversight role needs; RLS backs this up (the underlying
/// `customers` table is invisible to anyone else), this tab just isn't
/// wired into the nav for them in the first place - see
/// `admin_shell_screen.dart`.
class ConsoleCustomersTab extends ConsumerStatefulWidget {
  const ConsoleCustomersTab({super.key});

  @override
  ConsumerState<ConsoleCustomersTab> createState() =>
      _ConsoleCustomersTabState();
}

class _ConsoleCustomersTabState extends ConsumerState<ConsoleCustomersTab> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final customersState = ref.watch(allCustomersProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search by name, phone, or email',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _filter = value.trim()),
          ),
        ),
        Expanded(
          child: AsyncValueView<List<Customer>>(
            value: customersState,
            data: (customers) {
              final filtered = _filter.isEmpty
                  ? customers
                  : customers.where((c) {
                      final needle = _filter.toLowerCase();
                      return c.fullName.toLowerCase().contains(needle) ||
                          c.phone.toLowerCase().contains(needle) ||
                          (c.email?.toLowerCase().contains(needle) ?? false);
                    }).toList();

              if (customers.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No customers yet - one shows up here the moment '
                      'their first delivery request comes in.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                );
              }
              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    'No customer matches "$_filter".',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) =>
                    _CustomerCard(customer: filtered[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ExpansionTile(
        title: Text(
          customer.fullName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          customer.email?.isNotEmpty == true
              ? '${customer.phone} · ${customer.email}'
              : customer.phone,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customer.address?.isNotEmpty == true) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          customer.address!,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Delivery history',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Consumer(
                  builder: (context, ref, _) {
                    final historyState = ref.watch(
                      customerDeliveryHistoryProvider(customer.phone),
                    );
                    return AsyncValueView<List<Delivery>>(
                      value: historyState,
                      data: (deliveries) {
                        if (deliveries.isEmpty) {
                          return Text(
                            'No deliveries on file.',
                            style: TextStyle(color: Colors.grey.shade500),
                          );
                        }
                        return Column(
                          children: [
                            for (final delivery in deliveries)
                              _HistoryRow(delivery: delivery),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.delivery});

  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${delivery.trackingCode}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  DateFormat(
                    'd MMM yyyy, h:mm a',
                  ).format(delivery.createdAt.toLocal()),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          StatusBadge(status: delivery.status),
        ],
      ),
    );
  }
}
