import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One labeled point on a [TrendChart].
class TrendPoint {
  const TrendPoint(this.label, this.value);

  /// A short x-axis label (e.g. "Mon", "W12") - only a sparse subset is
  /// actually drawn, see [TrendChart.labelEvery].
  final String label;
  final double value;
}

/// A single-series line chart for the Console Dashboard's trend tiles
/// (delivery volume, revenue/commission over time) - deliberately one
/// series per chart rather than a dual-axis chart, since the two trends
/// shown here (a count and a money amount) don't share a meaningful
/// scale anyway.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.points,
    required this.color,
    this.height = 160,
    this.labelEvery = 1,
    this.valueFormatter,
  });

  final List<TrendPoint> points;
  final Color color;
  final double height;

  /// Draw an x-axis label every Nth point rather than every point, so a
  /// chart covering many points (weekly data over months) doesn't
  /// collide labels into unreadable overlap.
  final int labelEvery;

  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough history yet',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
          ),
        ),
      );
    }

    final maxY = points.map((p) => p.value).fold<double>(0, (a, b) => a > b ? a : b);
    final spots = [
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value),
    ];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY <= 0 ? 1 : maxY / 3,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: const Color(0xFFEFF1F4), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) => Text(
                  valueFormatter?.call(value) ?? value.toStringAsFixed(0),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= points.length || i % labelEvery != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      points[i].label,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 10.5,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final i = spot.x.round();
                final label = i >= 0 && i < points.length ? points[i].label : '';
                final text = valueFormatter?.call(spot.y) ?? spot.y.toStringAsFixed(0);
                return LineTooltipItem(
                  '$label\n$text',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
