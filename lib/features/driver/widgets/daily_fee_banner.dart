import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/driver_daily_fee_repository.dart';
import '../../../models/daily_fee_status.dart';

/// Opens the Mobile Money / manual-reference sheet for settling today's
/// balance - today's tiered platform fee (Console > Settings > Driver
/// daily fee) plus any per-delivery commission still due (see
/// `0050_bundle_commission_with_daily_fee.sql`), paid together.
///
/// This used to be a full banner pinned to the top of the driver
/// dashboard: a heading, a breakdown line, an explanation and a
/// full-width button, all in a coloured block. Accurate, but it pushed
/// the deliveries - the thing a driver actually opens the app for - most
/// of the way down the screen, and it sat there for the whole shift.
/// [DriverBalanceChip] carries the same information in one line now, and
/// this is what it opens.
///
/// [feeAmount] is the combined live balance still due - not necessarily
/// the full tier amount, since it shrinks after a partial payment and
/// grows again on crossing into a higher tier or completing another
/// delivery.
Future<void> showDailyFeePaymentSheet(
  BuildContext context, {
  required double feeAmount,
  required String currency,
  required String? driverPhone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _DailyFeePaymentSheet(
      feeAmount: feeAmount,
      currency: currency,
      driverPhone: driverPhone,
    ),
  );
}

/// The one-line stand-in for that old banner: what's owed, and a tap
/// straight into the payment sheet. Colour still carries the urgency
/// (amber while a payment is being confirmed, red when it's blocking new
/// work), because this is a real hard block in the database - a driver
/// who owes from a previous day cannot be assigned anything (see
/// `0037_tiered_daily_fee.sql`), and hiding that would just leave them
/// wondering why the work dried up.
class DriverBalanceChip extends StatelessWidget {
  const DriverBalanceChip({
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
    final pending = status == DailyFeeStatus.pending;
    final color = pending ? AppTheme.warning : AppTheme.danger;

    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showDailyFeePaymentSheet(
          context,
          feeAmount: feeAmount,
          currency: currency,
          driverPhone: driverPhone,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                pending ? Icons.hourglass_top : Icons.account_balance_wallet,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                pending
                    ? 'Confirming $currency ${feeAmount.toStringAsFixed(2)}'
                    : 'Pay $currency ${feeAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: color,
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: color),
            ],
          ),
        ),
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

  Future<void> _payViaPaystack() async {
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
          .chargeViaPaystack(phone: phone, network: _network);
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
              onPressed: _isCharging ? null : _payViaPaystack,
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
