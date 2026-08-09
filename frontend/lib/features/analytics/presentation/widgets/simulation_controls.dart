import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/analytics/presentation/analytics_view_model.dart';

/// The simulate/export/clear controls at the top of the analytics screen.
class SimulationControls extends ConsumerStatefulWidget {
  const SimulationControls({super.key});

  @override
  ConsumerState<SimulationControls> createState() => _SimulationControlsState();
}

class _SimulationControlsState extends ConsumerState<SimulationControls> {
  static const _presets = [1000, 10000, 100000];

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

  Future<void> _copyJson() async {
    final handCount = ref.read(analyticsViewModelProvider).handCount;
    final json = ref.read(analyticsViewModelProvider.notifier).exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied $handCount hands as JSON to clipboard')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsViewModelProvider);
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
        for (final preset in _presets)
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
          onSelectionChanged: busy ? null : (s) => vm.setButtonRotation(s.first),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          onPressed: busy || state.handCount == 0 ? null : _copyJson,
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

  static String _compact(int n) => n >= 1000 ? '${n ~/ 1000}k' : '$n';
}

/// The live progress bar shown while a simulation batch runs.
class SimulationProgress extends ConsumerWidget {
  const SimulationProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(analyticsViewModelProvider);
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
}
