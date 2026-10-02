import 'package:flutter/material.dart';

import '../../core/theme/console_design.dart';

/// A KPI tile for [TileGrid] with an optional trend delta against a prior
/// period. Flat surface + hairline border + a left accent edge, matching
/// [ConsoleCard]'s panel language rather than the soft-shadow cards this
/// superseded - see `console_design.dart`.
class TrendStatTile extends StatelessWidget {
  const TrendStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,

    /// Positive = up since the prior period, negative = down, null =
    /// no comparison available (e.g. not enough history yet).
    this.changeFraction,

    /// Whether an increase is the good direction for this metric - flips
    /// which way the delta is colored success/danger. Deliveries up is
    /// good; cancellations up is not.
    this.increaseIsGood = true,
  });

  final String label;
  final String value;
  final Color color;
  final double? changeFraction;
  final bool increaseIsGood;

  @override
  Widget build(BuildContext context) {
    final change = changeFraction;
    final isUp = (change ?? 0) > 0;
    final isFlat = change == null || change == 0;
    final changeColor = isFlat
        ? ConsoleColors.inkFaint
        : (isUp == increaseIsGood ? ConsoleColors.success : ConsoleColors.danger);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: ConsoleColors.surface,
        borderRadius: BorderRadius.circular(ConsoleRadius.md),
        border: Border(
          top: const BorderSide(color: ConsoleColors.border),
          right: const BorderSide(color: ConsoleColors.border),
          bottom: const BorderSide(color: ConsoleColors.border),
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: ConsoleText.eyebrow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: ConsoleText.statValue.copyWith(color: color)),
              if (change != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isFlat
                            ? Icons.remove
                            : (isUp ? Icons.arrow_upward : Icons.arrow_downward),
                        size: 12,
                        color: changeColor,
                      ),
                      Text(
                        '${(change.abs() * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: changeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
