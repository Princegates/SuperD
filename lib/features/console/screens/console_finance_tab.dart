import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/payment.dart';
import '../../../models/payment_method.dart';
import '../../../models/payment_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/console_providers.dart';

/// Revenue and payment reconciliation across every delivery - grouped by
/// currency (most self-hosted instances only ever use one, but nothing
/// here assumes that), by status, and by method.
class ConsoleFinanceTab extends ConsumerWidget {
  const ConsoleFinanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsState = ref.watch(allPaymentsProvider);

    return AsyncValueView<List<Payment>>(
      value: paymentsState,
      data: (payments) {
        if (payments.isEmpty) {
          return Center(
            child: Text(
              'No payments recorded yet',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          );
        }

        final byCurrency = <String, List<Payment>>{};
        for (final p in payments) {
          byCurrency.putIfAbsent(p.currency, () => []).add(p);
        }

        final byMethod = <PaymentMethod, double>{};
        for (final p in payments.where((p) => p.status == PaymentStatus.paid)) {
          byMethod.update(
            p.method,
            (sum) => sum + p.amount,
            ifAbsent: () => p.amount,
          );
        }

        final recent = payments.take(20).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in byCurrency.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _CurrencySummary(
                  currency: entry.key,
                  payments: entry.value,
                ),
              ),
            if (byMethod.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Collected by method',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final method in PaymentMethod.values)
                        if (byMethod[method] != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Icon(
                                  method.icon,
                                  size: 18,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(method.label)),
                                Text(
                                  byMethod[method]!.toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recent payments',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final payment in recent) _PaymentRow(payment: payment),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CurrencySummary extends StatelessWidget {
  const _CurrencySummary({required this.currency, required this.payments});

  final String currency;
  final List<Payment> payments;

  double _sum(PaymentStatus status) => payments
      .where((p) => p.status == status)
      .fold(0.0, (sum, p) => sum + p.amount);

  @override
  Widget build(BuildContext context) {
    final paid = _sum(PaymentStatus.paid);
    final pending = _sum(PaymentStatus.pending);
    final failed = _sum(PaymentStatus.failed);
    final refunded = _sum(PaymentStatus.refunded);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currency,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _AmountTile(
                  label: 'Collected',
                  amount: paid,
                  currency: currency,
                  color: AppTheme.success,
                ),
                _AmountTile(
                  label: 'Outstanding',
                  amount: pending,
                  currency: currency,
                  color: AppTheme.warning,
                ),
                if (failed > 0)
                  _AmountTile(
                    label: 'Failed',
                    amount: failed,
                    currency: currency,
                    color: AppTheme.danger,
                  ),
                if (refunded > 0)
                  _AmountTile(
                    label: 'Refunded',
                    amount: refunded,
                    currency: currency,
                    color: AppTheme.neutral,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
  });

  final String label;
  final double amount;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$currency ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(payment.method.icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${payment.currency} ${payment.amount.toStringAsFixed(2)} · '
              '${payment.method.label}',
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: payment.status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              payment.status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: payment.status.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            DateFormat('dd MMM').format(payment.createdAt.toLocal()),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
