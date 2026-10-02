import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A KPI tile for [TileGrid] with an optional trend delta against a prior
/// period - the one piece every existing private `_StatTile` (duplicated
/// per Console tab) lacks. Visually matches those: white card, 16 radius,
/// a light border, value above label.
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
        ? Colors.grey.shade500
        : (isUp == increaseIsGood ? AppTheme.success : AppTheme.danger);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EAEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                ),
              ),
              if (change != null) ...[
                Icon(
                  isFlat
                      ? Icons.remove
                      : (isUp
                            ? Icons.arrow_upward
                            : Icons.arrow_downward),
                  size: 13,
                  color: changeColor,
                ),
                Text(
                  '${(change.abs() * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: changeColor,
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
