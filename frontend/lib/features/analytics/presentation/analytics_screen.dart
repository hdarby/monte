import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/analytics/presentation/analytics_view_model.dart';
import 'package:monte/features/analytics/presentation/widgets/data_tables.dart';
import 'package:monte/features/analytics/presentation/widgets/metric_bars.dart';
import 'package:monte/features/analytics/presentation/widgets/simulation_controls.dart';
import 'package:monte/features/analytics/presentation/widgets/tuning_section.dart';

/// Shows poker analytics (VPIP, PFR, Aggression, win rate) computed from the
/// recorded hand histories, with controls to simulate an arbitrary number of
/// hands and export the raw history as JSON.
///
/// Layout only — each section is its own widget in `widgets/` and reads the
/// [AnalyticsViewModel] directly.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                const SimulationControls(),
                if (state.isSimulating) ...[
                  const SizedBox(height: 16),
                  const SimulationProgress(),
                ],
                const SizedBox(height: 20),
                if (stats.isEmpty)
                  const _EmptyState()
                else ...[
                  PlayerStatsTable(
                    stats: stats,
                    behaviorById: state.behaviorById,
                  ),
                  const SizedBox(height: 28),
                  MetricBars(
                    title: 'Win rate (bb/100)',
                    stats: stats,
                    value: (s) => s.bbPer100,
                    max: MetricBars.symMax(stats.map((s) => s.bbPer100)),
                    color: const Color(0xFF66BB6A),
                    format: (v) => v.toStringAsFixed(1),
                    signed: true,
                  ),
                  MetricBars(
                    title: 'VPIP %',
                    stats: stats,
                    value: (s) => s.vpip,
                    max: 100,
                    color: const Color(0xFF4FC3F7),
                    format: (v) => '${v.toStringAsFixed(0)}%',
                  ),
                  MetricBars(
                    title: 'PFR %',
                    stats: stats,
                    value: (s) => s.pfr,
                    max: 100,
                    color: const Color(0xFFBA68C8),
                    format: (v) => '${v.toStringAsFixed(0)}%',
                  ),
                  MetricBars(
                    title: 'Aggression Factor (postflop)',
                    stats: stats,
                    value: (s) => s.aggressionFactor,
                    max: MetricBars.niceMax(
                      stats.map((s) => s.aggressionFactor),
                    ),
                    color: AppTheme.chip,
                    format: (v) =>
                        v == double.infinity ? '∞' : v.toStringAsFixed(2),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(color: Colors.white12),
                const SizedBox(height: 16),
                const TuningSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown before any hands exist, pointing at how to produce some.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 60),
    child: Text(
      'No hands recorded yet.\n'
      'Set bot personalities in a New Game, then simulate hands '
      'here to see how each style performs.',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.white54, fontSize: 16),
    ),
  );
}
