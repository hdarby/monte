import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poker_client/core/theme/app_theme.dart';
import 'package:poker_client/features/analytics/domain/analytics.dart';
import 'package:poker_client/features/analytics/presentation/analytics_view_model.dart';

/// Shows poker analytics (VPIP, PFR, Aggression, win rate) computed from the
/// recorded hand histories, with controls to simulate more hands and export the
/// raw history as JSON. A pure consumer of [analyticsViewModelProvider].
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analyticsViewModelProvider);
    final stats = state.stats;
    final handCount = state.handCount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: AppTheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _controls(context, ref, handCount),
                const SizedBox(height: 20),
                if (stats.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Text(
                      'No hands recorded yet.\nSimulate some hands to see analytics.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  )
                else ...[
                  _statsTable(stats),
                  const SizedBox(height: 28),
                  _MetricBars(
                    title: 'VPIP %',
                    stats: stats,
                    value: (s) => s.vpip,
                    max: 100,
                    color: const Color(0xFF4FC3F7),
                    format: (v) => '${v.toStringAsFixed(0)}%',
                  ),
                  _MetricBars(
                    title: 'PFR %',
                    stats: stats,
                    value: (s) => s.pfr,
                    max: 100,
                    color: const Color(0xFFBA68C8),
                    format: (v) => '${v.toStringAsFixed(0)}%',
                  ),
                  _MetricBars(
                    title: 'Aggression Factor (postflop)',
                    stats: stats,
                    value: (s) => s.aggressionFactor,
                    max: _niceMax(stats.map((s) => s.aggressionFactor)),
                    color: AppTheme.chip,
                    format: (v) =>
                        v == double.infinity ? '∞' : v.toStringAsFixed(2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, WidgetRef ref, int handCount) {
    final vm = ref.read(analyticsViewModelProvider.notifier);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '$handCount hands recorded',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: Colors.black,
          ),
          icon: const Icon(Icons.fast_forward),
          onPressed: () => vm.simulate(100),
          label: const Text('Simulate 100'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: Colors.black,
          ),
          icon: const Icon(Icons.fast_forward),
          onPressed: () => vm.simulate(1000),
          label: const Text('Simulate 1000'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          onPressed: handCount == 0 ? null : () => _exportJson(context, ref),
          label: const Text('Copy JSON'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline),
          onPressed: handCount == 0 ? null : vm.clear,
          label: const Text('Clear'),
        ),
      ],
    );
  }

  Future<void> _exportJson(BuildContext context, WidgetRef ref) async {
    final handCount = ref.read(analyticsViewModelProvider).handCount;
    final json = ref.read(analyticsViewModelProvider.notifier).exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied $handCount hands as JSON to clipboard')),
      );
    }
  }

  Widget _statsTable(List<PlayerStats> stats) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Player')),
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
                  DataCell(Text('${s.hands}')),
                  DataCell(Text(s.vpip.toStringAsFixed(0))),
                  DataCell(Text(s.pfr.toStringAsFixed(0))),
                  DataCell(Text(s.aggressionLabel)),
                  DataCell(
                    Text(
                      s.bbPer100.toStringAsFixed(1),
                      style: TextStyle(
                        color: s.bbPer100 >= 0
                            ? const Color(0xFF66BB6A)
                            : const Color(0xFFEF5350),
                      ),
                    ),
                  ),
                  DataCell(Text('${s.netChips}')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static double _niceMax(Iterable<double> values) {
    final finite = values.where((v) => v != double.infinity);
    final m = finite.isEmpty ? 1.0 : finite.reduce((a, b) => a > b ? a : b);
    return m <= 0 ? 1 : m;
  }
}

/// A simple horizontal bar chart of one metric across players.
class _MetricBars extends StatelessWidget {
  const _MetricBars({
    required this.title,
    required this.stats,
    required this.value,
    required this.max,
    required this.color,
    required this.format,
  });

  final String title;
  final List<PlayerStats> stats;
  final double Function(PlayerStats) value;
  final double max;
  final Color color;
  final String Function(double) format;

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
                    child: Stack(
                      children: [
                        Container(
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: _factor(value(s)),
                          child: Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
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

  double _factor(double v) {
    if (v == double.infinity) return 1;
    if (max <= 0) return 0;
    return (v / max).clamp(0.0, 1.0);
  }
}
