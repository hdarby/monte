import 'package:flutter/material.dart';

import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/presentation/bot_lineup_editor.dart';
import 'package:monte/core/theme/app_theme.dart';

/// Pre-game setup: lets the player set each bot seat's behavior model before a
/// fresh game is dealt — either a custom brain + playing style, or a calibrated
/// named pro. Returns the chosen specs in seat order (one per bot, human
/// excluded), or null if the player cancels.
Future<List<BotSpec>?> showNewGameDialog(
  BuildContext context, {
  required List<String> seatNames,
  required List<BotSpec> initial,
}) {
  return showDialog<List<BotSpec>>(
    context: context,
    builder: (_) => _NewGameDialog(seatNames: seatNames, initial: initial),
  );
}

class _NewGameDialog extends StatefulWidget {
  const _NewGameDialog({required this.seatNames, required this.initial});

  final List<String> seatNames;
  final List<BotSpec> initial;

  @override
  State<_NewGameDialog> createState() => _NewGameDialogState();
}

class _NewGameDialogState extends State<_NewGameDialog> {
  late List<BotSpec> _specs = List.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('New game'),
      content: SizedBox(
        width: 660,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set each opponent, then deal. Pick a named Pro for a '
              'stat-calibrated player, or a custom Brain + Personality.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: BotLineupEditor(
                  seatNames: widget.seatNames,
                  specs: _specs,
                  onChanged: (s) => setState(() => _specs = s),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.pop(context, _specs),
          child: const Text('Deal'),
        ),
      ],
    );
  }
}
