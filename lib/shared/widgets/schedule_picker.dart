import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

/// "As soon as possible" vs "Schedule for later", with a date+time picker
/// that only appears once the second option is chosen. Used by both the
/// customer-facing request form and the dispatcher's create-delivery form
/// - [value] is null for ASAP, a future [DateTime] once scheduled.
class SchedulePicker extends StatelessWidget {
  const SchedulePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value ?? now.add(const Duration(minutes: 30));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (picked.isBefore(DateTime.now())) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please pick a time in the future')),
        );
      }
      return;
    }
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final isScheduled = value != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Text('As soon as possible'),
                selected: !isScheduled,
                onSelected: (_) => onChanged(null),
                selectedColor: AppTheme.primaryLight,
                labelStyle: TextStyle(
                  color: !isScheduled ? AppTheme.primary : Colors.black87,
                  fontWeight: !isScheduled ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                label: const Text('Schedule for later'),
                selected: isScheduled,
                onSelected: (_) => _pick(context),
                selectedColor: AppTheme.primaryLight,
                labelStyle: TextStyle(
                  color: isScheduled ? AppTheme.primary : Colors.black87,
                  fontWeight: isScheduled ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (isScheduled) ...[
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _pick(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('EEE d MMM, h:mm a').format(value!),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
