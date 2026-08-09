import 'package:flutter/material.dart';
import 'package:monte/features/analytics/domain/analytics.dart';

/// A simple horizontal bar chart of one metric across players. When [signed],
/// bars grow from a centre line so wins (right) and losses (left) are clear.
class MetricBars extends StatelessWidget {
  const MetricBars({
    super.key,
    required this.title,
    required this.stats,
    required this.value,
    required this.max,
    required this.color,
    required this.format,
    this.signed = false,
  });

  final String title;
  final List<PlayerStats> stats;
  final double Function(PlayerStats) value;
  final double max;
  final Color color;
  final String Function(double) format;
  final bool signed;

  /// The largest finite value in [values], floored at 1 so an all-zero metric
  /// still renders a sane axis.
  static double niceMax(Iterable<double> values) {
    final finite = values.where((v) => v != double.infinity);
    final m = finite.isEmpty ? 1.0 : finite.reduce((a, b) => a > b ? a : b);
    return m <= 0 ? 1 : m;
  }

  /// A symmetric max for signed metrics (so 0 sits in the middle of the bar).
  static double symMax(Iterable<double> values) {
    var m = 1.0;
    for (final v in values) {
      if (v.isFinite && v.abs() > m) m = v.abs();
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          for (final s in stats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(
                      s.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: signed ? _signedBar(value(s)) : _bar(value(s)),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 60,
                    child: Text(
                      format(value(s)),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(double v) => Stack(
    children: [
      _track(),
      FractionallySizedBox(widthFactor: _factor(v), child: _fill(color)),
    ],
  );

  /// A centre-origin bar: positive grows right (green), negative left (red).
  Widget _signedBar(double v) {
    final frac = max <= 0 ? 0.0 : (v.abs() / max).clamp(0.0, 1.0);
    final positive = v >= 0;
    return Stack(
      children: [
        _track(),
        Row(
          children: [
            // Left half — losses grow leftward from the centre.
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: positive ? 0.0 : frac,
                  child: _fill(const Color(0xFFEF5350)),
                ),
              ),
            ),
            // Right half — wins grow rightward from the centre.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: positive ? frac : 0.0,
                  child: _fill(color),
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.center,
          child: Container(width: 1, height: 22, color: Colors.white24),
        ),
      ],
    );
  }

  Widget _track() => Container(
    height: 22,
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(6),
    ),
  );

  Widget _fill(Color c) => Container(
    height: 22,
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
  );

  double _factor(double v) {
    if (v == double.infinity) return 1;
    if (max <= 0) return 0;
    return (v / max).clamp(0.0, 1.0);
  }
}
