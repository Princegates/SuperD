import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/delivery_failure_reason.dart';

/// The one place a failed delivery gets its reason, whether the rider is
/// recording it at the gate or a dispatcher is entering what the rider
/// phoned in. Same list, same wording, so a month of these can actually
/// be counted.
///
/// Returns null if they backed out. Nothing is written until the button
/// at the bottom is pressed - ending someone's delivery is not something
/// to do on a stray tap.
typedef DeliveryFailure = ({DeliveryFailureReason reason, String? note});

Future<DeliveryFailure?> showFailDeliverySheet(
  BuildContext context, {
  required String customerName,

  /// The rider is telling us what just happened to them; a dispatcher is
  /// writing down what someone else told them. Only the wording differs.
  bool asRider = true,
}) {
  return showModalBottomSheet<DeliveryFailure>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _FailDeliverySheet(customerName: customerName, asRider: asRider),
    ),
  );
}

class _FailDeliverySheet extends StatefulWidget {
  const _FailDeliverySheet({required this.customerName, required this.asRider});

  final String customerName;
  final bool asRider;

  @override
  State<_FailDeliverySheet> createState() => _FailDeliverySheetState();
}

class _FailDeliverySheetState extends State<_FailDeliverySheet> {
  DeliveryFailureReason? _reason;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason;
    if (reason == null) return;
    final note = _noteController.text.trim();
    Navigator.of(context)
        .pop((reason: reason, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    // "Other" without a word of explanation is a row nobody can act on
    // later, so it is the one reason that asks for the note.
    final needsNote =
        _reason == DeliveryFailureReason.other &&
        _noteController.text.trim().isEmpty;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            widget.asRider
                ? "Couldn't deliver this"
                : 'Record a failed delivery',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            widget.asRider
                ? 'This ends the delivery for ${widget.customerName} and tells '
                      'dispatch what happened. You keep no further '
                      'responsibility for the package once you have handed it '
                      'back.'
                : 'Ends the delivery for ${widget.customerName} and records why, '
                      'separately from an order called off before anyone rode.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          for (final reason in DeliveryFailureReason.values)
            _ReasonTile(
              reason: reason,
              selected: _reason == reason,
              onTap: () => setState(() => _reason = reason),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteController,
            onChanged: (_) => setState(() {}),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _reason == DeliveryFailureReason.other
                  ? 'What happened?'
                  : 'Anything to add? (optional)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.warning,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _reason == null || needsNote ? null : _submit,
            child: const Text('Record as failed'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: Text(widget.asRider ? 'Keep trying' : 'Never mind'),
          ),
        ],
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final DeliveryFailureReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.warning.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
              color: selected ? AppTheme.warning : Colors.grey.shade300,
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                reason.icon,
                size: 20,
                color: selected ? AppTheme.warning : Colors.grey.shade600,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reason.riderLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason.hint,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 20, color: AppTheme.warning),
            ],
          ),
        ),
      ),
    );
  }
}
