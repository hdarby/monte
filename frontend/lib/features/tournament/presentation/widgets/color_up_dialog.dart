import 'package:flutter/material.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';

/// Announces a color-up (chip race): which chip was retired, the new smallest
/// denomination, and who won or lost chips in the race.
class ColorUpDialog extends StatelessWidget {
  const ColorUpDialog({super.key, required this.colorUp});
  final ColorUpDisplay colorUp;

  @override
  Widget build(BuildContext context) {
    final movers = colorUp.rows.where((r) => r.delta != 0).toList();
    return AlertDialog(
      title: Text('Color up: ${formatChips(colorUp.retiredUnit)} chips raced off'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Smallest chip in play is now ${formatChips(colorUp.newUnit)}.',
          ),
          const SizedBox(height: 12),
          if (movers.isEmpty)
            const Text('Everyone had exact change — no chips changed hands.')
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: [for (final r in movers) _RaceRow(row: r)],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// One player's net result from the chip race.
class _RaceRow extends StatelessWidget {
  const _RaceRow({required this.row});
  final ColorUpRow row;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            displayName(row.name, isHuman: row.isHuman),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: row.isHuman ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          '${row.delta > 0 ? '+' : ''}${formatChips(row.delta)}',
          style: TextStyle(color: row.delta > 0 ? Colors.green : Colors.red),
        ),
      ],
    ),
  );
}
