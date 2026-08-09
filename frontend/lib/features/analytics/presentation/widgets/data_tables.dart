import 'package:flutter/material.dart';
import 'package:monte/features/analytics/domain/analytics.dart';
import 'package:monte/features/eval_history/domain/eval_metrics.dart';

/// Green for a winning rate, red for a losing one.
const _win = Color(0xFF66BB6A);
const _loss = Color(0xFFEF5350);

/// Shared chrome for the analytics tables: a rounded, bordered, horizontally
/// scrollable panel.
class _TablePanel extends StatelessWidget {
  const _TablePanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.black26,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    ),
  );
}

/// A bb/100 cell, coloured by whether the rate is winning or losing.
DataCell _rateCell(double bbPer100) => DataCell(
  Text(
    bbPer100.toStringAsFixed(1),
    style: TextStyle(
      color: bbPer100 >= 0 ? _win : _loss,
      fontWeight: FontWeight.w600,
    ),
  ),
);

/// Per-player results for the current session's recorded hands.
class PlayerStatsTable extends StatelessWidget {
  const PlayerStatsTable({
    super.key,
    required this.stats,
    required this.behaviorById,
  });

  final List<PlayerStats> stats;

  /// Player id -> behavior label (brain + style), so each row shows which
  /// personality it represents.
  final Map<String, String> behaviorById;

  @override
  Widget build(BuildContext context) => _TablePanel(
    child: DataTable(
      columns: const [
        DataColumn(label: Text('Player')),
        DataColumn(label: Text('Style')),
        DataColumn(label: Text('Hands'), numeric: true),
        DataColumn(label: Text('VPIP%'), numeric: true),
        DataColumn(label: Text('PFR%'), numeric: true),
        DataColumn(label: Text('AF'), numeric: true),
        DataColumn(label: Text('bb/100'), numeric: true),
        DataColumn(label: Text('Net'), numeric: true),
      ],
      rows: [
        for (final s in stats)
          DataRow(
            cells: [
              DataCell(Text(s.name)),
              DataCell(
                Text(
                  behaviorById[s.id] ?? '—',
                  style: const TextStyle(color: Colors.white60),
                ),
              ),
              DataCell(Text('${s.hands}')),
              DataCell(Text(s.vpip.toStringAsFixed(0))),
              DataCell(Text(s.pfr.toStringAsFixed(0))),
              DataCell(Text(s.aggressionLabel)),
              _rateCell(s.bbPer100),
              DataCell(Text('${s.netChips}')),
            ],
          ),
      ],
    ),
  );
}

/// Per-model metrics from the permanent full-information tuning history, with
/// each model's VPIP target alongside its actual.
class TuningMetricsTable extends StatelessWidget {
  const TuningMetricsTable({super.key, required this.metrics});
  final List<ModelMetrics> metrics;

  static String _pct(double v) => v.toStringAsFixed(0);

  static String _vpipCell(ModelMetrics m) {
    final t = m.vpipTarget;
    return t == null ? _pct(m.vpip) : '${_pct(m.vpip)} (t${_pct(t)})';
  }

  @override
  Widget build(BuildContext context) => _TablePanel(
    child: DataTable(
      columns: const [
        DataColumn(label: Text('Model')),
        DataColumn(label: Text('Hands'), numeric: true),
        DataColumn(label: Text('VPIP% (t)'), numeric: true),
        DataColumn(label: Text('PFR%'), numeric: true),
        DataColumn(label: Text('3B%'), numeric: true),
        DataColumn(label: Text('Limp%'), numeric: true),
        DataColumn(label: Text('AF'), numeric: true),
        DataColumn(label: Text('Steal%'), numeric: true),
        DataColumn(label: Text('StlWin%'), numeric: true),
        DataColumn(label: Text('FoldRvr%'), numeric: true),
        DataColumn(label: Text('WTSD%'), numeric: true),
        DataColumn(label: Text('bb/100'), numeric: true),
      ],
      rows: [
        for (final m in metrics)
          DataRow(
            cells: [
              DataCell(Text(m.modelLabel)),
              DataCell(Text('${m.hands}')),
              DataCell(Text(_vpipCell(m))),
              DataCell(Text(_pct(m.pfr))),
              DataCell(Text(_pct(m.threeBet))),
              DataCell(Text(_pct(m.limp))),
              DataCell(
                Text(
                  m.aggressionFactor == double.infinity
                      ? '∞'
                      : m.aggressionFactor.toStringAsFixed(2),
                ),
              ),
              DataCell(Text(_pct(m.stealAttemptPct))),
              DataCell(Text(_pct(m.stealSuccessPct))),
              DataCell(Text(_pct(m.foldToRiverBet))),
              DataCell(Text(_pct(m.wtsd))),
              _rateCell(m.bbPer100),
            ],
          ),
      ],
    ),
  );
}
