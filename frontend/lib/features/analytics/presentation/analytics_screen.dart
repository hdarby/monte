import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/analytics/domain/analytics.dart';
import 'package:monte/features/analytics/presentation/analytics_view_model.dart';

/// Shows poker analytics (VPIP, PFR, Aggression, win rate) computed from the
/// recorded hand histories, with controls to simulate an arbitrary number of
/// hands and export the raw history as JSON.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  final _handsController = TextEditingController(text: '10000');

  @override
  void dispose() {
    _handsController.dispose();
    super.dispose();
  }

  void _runFromField() {
    final n = int.tryParse(_handsController.text.trim());
    if (n != null && n > 0) {
      ref.read(analyticsViewModelProvider.notifier).simulate(n);
    }
  }

  void _runPreset(int n) {
    _handsController.text = '$n';
    ref.read(analyticsViewModelProvider.notifier).simulate(n);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsViewModelProvider);
    final stats = state.stats;
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
                _controls(state),
                if (state.isSimulating) ...[
                  const SizedBox(height: 16),
                  _progress(state),
                ],
                const SizedBox(height: 20),
                if (stats.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Text(
                      'No hands recorded yet.\n'
                      'Set bot personalities in a New Game, then simulate hands '
                      'here to see how each style performs.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  )
                else ...[
                  _statsTable(stats, state.behaviorById),
                  const SizedBox(height: 28),
                  _MetricBars(
                    title: 'Win rate (bb/100)',
                    stats: stats,
                    value: (s) => s.bbPer100,
                    max: _symMax(stats.map((s) => s.bbPer100)),
                    color: const Color(0xFF66BB6A),
                    format: (v) => v.toStringAsFixed(1),
                    signed: true,
                  ),
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

  Widget _controls(AnalyticsState state) {
    final vm = ref.read(analyticsViewModelProvider.notifier);
    final busy = state.isSimulating;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${state.handCount} hands recorded',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          child: TextField(
            controller: _handsController,
            enabled: !busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Hands',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _runFromField(),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: Colors.black,
          ),
          icon: const Icon(Icons.fast_forward),
          onPressed: busy ? null : _runFromField,
          label: const Text('Simulate'),
        ),
        for (final preset in const [1000, 10000, 100000])
          OutlinedButton(
            onPressed: busy ? null : () => _runPreset(preset),
            child: Text(_compact(preset)),
          ),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Rotate'),
              icon: Icon(Icons.sync, size: 16),
            ),
            ButtonSegment(
              value: false,
              label: Text('Fixed'),
              icon: Icon(Icons.push_pin, size: 16),
            ),
          ],
          selected: {state.rotateButton},
          onSelectionChanged:
              busy ? null : (s) => vm.setButtonRotation(s.first),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          onPressed: busy || state.handCount == 0
              ? null
              : () => _exportJson(context),
          label: const Text('Copy JSON'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline),
          onPressed: busy || state.handCount == 0 ? null : vm.clear,
          label: const Text('Clear'),
        ),
      ],
    );
  }

  Widget _progress(AnalyticsState state) {
    final vm = ref.read(analyticsViewModelProvider.notifier);
    final pct = (state.progress * 100).toStringAsFixed(0);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Simulating ${state.simulated} / ${state.target}  ($pct%)',
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: state.progress == 0 ? null : state.progress,
                  minHeight: 8,
                  backgroundColor: Colors.white10,
                  color: AppTheme.gold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.stop),
          onPressed: vm.stopSimulation,
          label: const Text('Stop'),
        ),
      ],
    );
  }

  Future<void> _exportJson(BuildContext context) async {
    final handCount = ref.read(analyticsViewModelProvider).handCount;
    final json = ref.read(analyticsViewModelProvider.notifier).exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied $handCount hands as JSON to clipboard')),
      );
    }
  }

  Widget _statsTable(List<PlayerStats> stats, Map<String, String> behavior) {
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
                      behavior[s.id] ?? '—',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
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
                        fontWeight: FontWeight.w600,
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

  static String _compact(int n) =>
      n >= 1000 ? '${n ~/ 1000}k' : '$n';

  static double _niceMax(Iterable<double> values) {
    final finite = values.where((v) => v != double.infinity);
    final m = finite.isEmpty ? 1.0 : finite.reduce((a, b) => a > b ? a : b);
    return m <= 0 ? 1 : m;
  }

  /// A symmetric max for signed metrics (so 0 sits in the middle of the bar).
  static double _symMax(Iterable<double> values) {
    var m = 1.0;
    for (final v in values) {
      if (v.isFinite && v.abs() > m) m = v.abs();
    }
    return m;
  }
}

/// A simple horizontal bar chart of one metric across players. When [signed],
/// bars grow from a centre line so wins (right) and losses (left) are clear.
class _MetricBars extends StatelessWidget {
  const _MetricBars({
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
      FractionallySizedBox(
        widthFactor: _factor(v),
        child: _fill(color),
      ),
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
