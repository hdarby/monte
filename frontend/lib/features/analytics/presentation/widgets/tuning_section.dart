import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/analytics/presentation/analytics_view_model.dart';
import 'package:monte/features/analytics/presentation/widgets/data_tables.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';

/// The permanent, full-information tuning history — recorded for every hand
/// (live and simulated), including folded cards, and never shown to a bot.
///
/// See `features/eval_history/` for the store behind it, and the "two hand
/// records" note in CLAUDE.md for why it is kept separate from `HandHistory`.
class TuningSection extends ConsumerWidget {
  const TuningSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analyticsViewModelProvider);
    final vm = ref.read(analyticsViewModelProvider.notifier);
    final busy = state.isSimulating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tuning history (permanent)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          '${state.tuningCount} hands recorded — full information (incl. folded '
          'cards, positions, model per seat). Never shown to bots; persists '
          'across sessions until wiped.',
          style: const TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.insights),
              onPressed: busy || state.tuningLoading ? null : vm.loadTuning,
              label: const Text('Load metrics by model'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.download),
              onPressed: busy ? null : () => _exportTuning(context, ref),
              label: const Text('Export full JSON'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: Colors.black,
              ),
              icon: const Icon(Icons.auto_fix_high),
              onPressed: busy ? null : () => _autoTune(context, ref),
              label: const Text('Auto-tune personalities'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF5350),
              ),
              icon: const Icon(Icons.delete_forever),
              onPressed: busy ? null : () => _confirmWipe(context, ref),
              label: const Text('Wipe tuning history'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _AdjustmentsStatus(),
        if (state.tuningLoading) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(
            minHeight: 4,
            backgroundColor: Colors.white10,
            color: AppTheme.gold,
          ),
        ],
        if (state.tuningMetrics.isNotEmpty) ...[
          const SizedBox(height: 16),
          TuningMetricsTable(metrics: state.tuningMetrics),
        ],
      ],
    );
  }

  static Future<void> _exportTuning(BuildContext context, WidgetRef ref) async {
    final json = await ref
        .read(analyticsViewModelProvider.notifier)
        .tuningExportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      _toast(context, 'Copied full-information tuning history to clipboard');
    }
  }

  static Future<void> _autoTune(BuildContext context, WidgetRef ref) async {
    final changed = await ref
        .read(analyticsViewModelProvider.notifier)
        .autoTunePersonalities();
    if (!context.mounted) return;
    _toast(
      context,
      changed == 0
          ? 'No models had enough hands to tune (need ~300+). Simulate more, '
                'then auto-tune again.'
          : 'Auto-tuned $changed ${changed == 1 ? 'personality' : 'personalities'} '
                'toward target. Tuning history reset — simulate again to refine.',
    );
  }

  static Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Wipe tuning history?'),
        content: const Text(
          'Permanently deletes the recorded full-information hand history and '
          'resets in-session opponent reads. Do this after changing a model so '
          'old behavior can\'t pollute tuning. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF5350),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wipe'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(analyticsViewModelProvider.notifier).wipeTuning();
    if (context.mounted) _toast(context, 'Tuning history wiped');
  }

  static void _toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
}

/// Whether the offline auto-tuner currently has any personality overrides
/// applied, with a way to revert them.
class _AdjustmentsStatus extends ConsumerWidget {
  const _AdjustmentsStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(profileOverridesProvider).length;
    if (n == 0) {
      return const Text(
        'No tuning adjustments applied — personalities use their code defaults.',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      );
    }
    return Row(
      children: [
        Text(
          '$n ${n == 1 ? 'personality' : 'personalities'} currently adjusted '
          'by the tuner.',
          style: const TextStyle(color: AppTheme.gold, fontSize: 12),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => _reset(context, ref),
          child: const Text('Reset adjustments'),
        ),
      ],
    );
  }

  static Future<void> _reset(BuildContext context, WidgetRef ref) async {
    await ref.read(analyticsViewModelProvider.notifier).resetTuningAdjustments();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Adjustments cleared — personalities reverted to defaults',
          ),
        ),
      );
    }
  }
}
