import 'package:flutter/material.dart';

import 'package:monte/core/presentation/money_format.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/coach/domain/hand_coach.dart';

/// Shows the in-hand coach as a themed, scrollable dialog. The [report] is
/// computed once by the caller from the current snapshot.
Future<void> showCoachDialog(
  BuildContext context,
  CoachReport report,
  MoneyFormat money,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CoachDialog(report: report, money: money),
  );
}

class _CoachDialog extends StatelessWidget {
  const _CoachDialog({required this.report, required this.money});

  final CoachReport report;
  final MoneyFormat money;

  @override
  Widget build(BuildContext context) {
    final r = report;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Row(
        children: [
          Icon(Icons.school, color: AppTheme.gold, size: 20),
          SizedBox(width: 8),
          Text('Coach'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _statsGrid(),
              const SizedBox(height: 14),
              _section('The spot', r.actionRead),
              _section('Their range', r.rangeRead),
              if (r.breakdown != null) _breakdown(r.breakdown!),
              if (r.polarized && r.polarizedNote != null)
                _callout(r.polarizedNote!),
              if (r.analysisAvailable) ...[
                const SizedBox(height: 8),
                const _Label('Expected value'),
                const SizedBox(height: 6),
                for (var k = 0; k < r.actions.length; k++)
                  _actionRow(r.actions[k], k == r.recommendedIndex),
                const SizedBox(height: 12),
                _recommendation(r.recommendation),
              ] else ...[
                const SizedBox(height: 12),
                const Text(
                  'Full action analysis is available when it\'s your turn.',
                  style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Directional estimates for learning — not exact GTO.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _statsGrid() {
    String pct(double v) => '${(v * 100).round()}%';
    String bb(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)} BB';
    final cells = <(String, String)>[
      ('Hand', report.madeHand),
      ('Equity', pct(report.equity)),
      ('SPR', report.spr.toStringAsFixed(1)),
      ('Stack', bb(report.stackBb)),
      ('Pot', bb(report.potBb)),
      if (report.potOdds != null) ('To call', bb(report.toCallBb)),
      if (report.potOdds != null) ('Pot odds', pct(report.potOdds!)),
      ('Opponents', '${report.opponents}'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final c in cells) _stat(c.$1, c.$2)],
    );
  }

  Widget _stat(String label, String value) => Container(
    width: 104,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black26,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: Colors.white38, fontSize: 10, letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.gold)),
      ],
    ),
  );

  Widget _section(String label, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        const SizedBox(height: 3),
        Text(body, style: const TextStyle(color: Colors.white70, height: 1.35)),
      ],
    ),
  );

  Widget _breakdown(RangeBreakdown b) {
    String pct(double v) => '${(v * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: (b.beat * 100).round().clamp(1, 100),
                child: Container(height: 10, color: const Color(0xFF66BB6A)),
              ),
              if (b.tie > 0)
                Expanded(
                  flex: (b.tie * 100).round().clamp(1, 100),
                  child: Container(height: 10, color: Colors.white38),
                ),
              Expanded(
                flex: (b.lose * 100).round().clamp(1, 100),
                child: Container(height: 10, color: const Color(0xFFEF5350)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Ahead of ${pct(b.beat)}'
            '${b.beatClasses.isEmpty ? '' : ' (${b.beatClasses.join(', ')})'} · '
            'behind ${pct(b.lose)}'
            '${b.loseClasses.isEmpty ? '' : ' (${b.loseClasses.join(', ')})'}',
            style: const TextStyle(color: Colors.white60, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _callout(String text) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: AppTheme.warnOrange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.warnOrange.withValues(alpha: 0.5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.bolt, color: AppTheme.warnOrange, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35)),
        ),
      ],
    ),
  );

  Widget _actionRow(ActionEv a, bool recommended) {
    final sizing = a.toAmount == null
        ? ''
        : ' ${money.format(a.toAmount!)}'
            '${a.sizingTag == null ? '' : ' (${a.sizingTag})'}';
    final ev = a.ev >= 0 ? '+${a.ev.round()}' : '${a.ev.round()}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: recommended ? AppTheme.gold.withValues(alpha: 0.12) : Colors.black26,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: recommended ? AppTheme.gold : Colors.white10,
          width: recommended ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          if (recommended) ...[
            const Icon(Icons.star, color: AppTheme.gold, size: 15),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.label}$sizing',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (a.note != null)
                  Text(a.note!,
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Text(ev,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: a.ev >= 0 ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
              )),
        ],
      ),
    );
  }

  Widget _recommendation(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.gold.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lightbulb, color: AppTheme.gold, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
        ),
      ],
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: Colors.white38,
      fontSize: 11,
      letterSpacing: 1.0,
      fontWeight: FontWeight.bold,
    ),
  );
}
