import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/driver_daily_fee_repository.dart';
import '../../../models/daily_fee_status.dart';

/// Shown at the top of the driver dashboard whenever today's tiered
/// platform fee (Console > Settings > Driver daily fee) has a balance
/// still owed - the UI side of a hard block enforced in the database (see
/// `0037_tiered_daily_fee.sql`): a driver in this state simply cannot be
/// given a new delivery, so this exists to make the reason obvious and
/// give them a way to fix it on the spot. [feeAmount] is the live balance
/// still due, not necessarily the full tier amount - it can shrink to 0
/// after a partial payment, or grow again after crossing into a higher
/// tier.
class DailyFeeBanner extends StatelessWidget {
  const DailyFeeBanner({
    super.key,
    required this.feeAmount,
    required this.currency,
    required this.status,
    required this.driverPhone,
  });

  final double feeAmount;
  final String currency;

  /// Null means no attempt has been made yet today.
  final DailyFeeStatus? status;
  final String? driverPhone;

  @override
  Widget build(BuildContext context) {
    final color = status == DailyFeeStatus.pending
        ? AppTheme.warning
        : AppTheme.danger;
    final message = switch (status) {
      DailyFeeStatus.pending =>
        "Payment pending - check your phone to approve it. This updates "
            'automatically once confirmed.',
      DailyFeeStatus.failed =>
        "Today's payment didn't go through - try again below.",
      _ =>
        "You haven't paid today's commission yet - pay to receive new "
            'deliveries.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: color.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Today's commission: $currency "
                  '${feeAmount.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(message, style: TextStyle(color: color, fontSize: 12.5)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => _DailyFeePaymentSheet(
                  feeAmount: feeAmount,
                  currency: currency,
                  driverPhone: driverPhone,
                ),
              ),
              child: Text(
                status == DailyFeeStatus.pending
                    ? 'Pay a different way'
                    : 'Pay now',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _networks = [
  (value: 'mtn-gh', label: 'MTN Mobile Money'),
  (value: 'vodafone-gh', label: 'Vodafone Cash'),
  (value: 'tigo-gh', label: 'AirtelTigo Money'),
];

class _DailyFeePaymentSheet extends ConsumerStatefulWidget {
  const _DailyFeePaymentSheet({
    required this.feeAmount,
    required this.currency,
    required this.driverPhone,
  });

  final double feeAmount;
  final String currency;
  final String? driverPhone;

  @override
  ConsumerState<_DailyFeePaymentSheet> createState() =>
      _DailyFeePaymentSheetState();
}

class _DailyFeePaymentSheetState extends ConsumerState<_DailyFeePaymentSheet> {
  late final _phoneController = TextEditingController(
    text: widget.driverPhone ?? '',
  );
  final _referenceController = TextEditingController();
  String _network = _networks.first.value;
  bool _isCharging = false;
  bool _isSubmittingManual = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _payViaHubtel() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter a Mobile Money number.');
      return;
    }
    setState(() {
      _isCharging = true;
      _error = null;
      _message = null;
    });
    try {
      final message = await ref
          .read(driverDailyFeeRepositoryProvider)
          .chargeViaHubtel(phone: phone, network: _network);
      if (mounted) setState(() => _message = message);
    } on DailyFeeException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isCharging = false);
    }
  }

  Future<void> _submitManualReference() async {
    final reference = _referenceController.text.trim();
    if (reference.isEmpty) {
      setState(() => _error = 'Enter the Mobile Money transaction reference.');
      return;
    }
    setState(() {
      _isSubmittingManual = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(driverDailyFeeRepositoryProvider)
          .submitManualPayment(reference);
      if (mounted) {
        setState(
          () => _message = 'Submitted - a dispatcher will confirm it shortly.',
        );
      }
    } on DailyFeeException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmittingManual = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Pay today's commission",
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.currency} ${widget.feeAmount.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Mobile Money number',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _network,
              decoration: const InputDecoration(labelText: 'Network'),
              items: [
                for (final n in _networks)
                  DropdownMenuItem(value: n.value, child: Text(n.label)),
              ],
              onChanged: (value) => setState(() => _network = value!),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _isCharging ? null : _payViaHubtel,
              child: _isCharging
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Pay via Mobile Money'),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or already paid another way?',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Mobile Money transaction reference',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _isSubmittingManual ? null : _submitManualReference,
              child: _isSubmittingManual
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Submit reference for review'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
