import 'package:flutter/material.dart';

import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';

/// Prompts the player about a busted [seat]: reload its bankroll, or (for a bot)
/// seat a fresh opponent with a chosen personality and a full stack.
Future<void> showBustOutDialog(
  BuildContext context, {
  required SeatView seat,
  required VoidCallback onReload,
  required void Function(PersonalityArchetype archetype) onReplace,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _BustOutDialog(seat: seat, onReload: onReload, onReplace: onReplace),
  );
}

class _BustOutDialog extends StatefulWidget {
  const _BustOutDialog({
    required this.seat,
    required this.onReload,
    required this.onReplace,
  });

  final SeatView seat;
  final VoidCallback onReload;
  final void Function(PersonalityArchetype archetype) onReplace;

  @override
  State<_BustOutDialog> createState() => _BustOutDialogState();
}

class _BustOutDialogState extends State<_BustOutDialog> {
  PersonalityArchetype _archetype = PersonalityArchetype.lag;

  @override
  Widget build(BuildContext context) {
    final seat = widget.seat;
    final isBot = !seat.isHuman;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(seat.isHuman ? 'You busted' : '${seat.name} busted'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            seat.isHuman
                ? "You're out of chips. Reload your bankroll to keep playing."
                : '${seat.name} is out of chips. Reload their bankroll, or '
                      'seat a new opponent with a fresh stack.',
            style: const TextStyle(color: Colors.white70),
          ),
          if (isBot) ...[
            const SizedBox(height: 20),
            const Text(
              'New opponent personality',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PersonalityArchetype>(
              initialValue: _archetype,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                for (final a in PersonalityArchetype.values)
                  DropdownMenuItem(value: a, child: Text(a.label)),
              ],
              onChanged: (v) => setState(() => _archetype = v!),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onReload();
            Navigator.of(context).pop();
          },
          child: Text(seat.isHuman ? 'Reload bankroll' : 'Reload ${seat.name}'),
        ),
        if (isBot)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              widget.onReplace(_archetype);
              Navigator.of(context).pop();
            },
            child: const Text('Seat new player'),
          ),
      ],
    );
  }
}
