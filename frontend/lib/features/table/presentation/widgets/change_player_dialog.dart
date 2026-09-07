import 'package:flutter/material.dart';

import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/core/util/format.dart';

/// Two-step "seat a different player" flow: Pro or Amateur, then pick a
/// specific catalog player — excluding anyone already seated at this table.
/// Returns the chosen [PlayerProfile], or null if cancelled.
Future<PlayerProfile?> showChangePlayerDialog(
  BuildContext context, {
  required Set<String?> seatedProfileIds,
}) {
  return showDialog<PlayerProfile>(
    context: context,
    builder: (_) => _ChangePlayerDialog(seatedProfileIds: seatedProfileIds),
  );
}

class _ChangePlayerDialog extends StatefulWidget {
  const _ChangePlayerDialog({required this.seatedProfileIds});

  final Set<String?> seatedProfileIds;

  @override
  State<_ChangePlayerDialog> createState() => _ChangePlayerDialogState();
}

class _ChangePlayerDialogState extends State<_ChangePlayerDialog> {
  /// Null until the player picks a kind — the dialog opens on that choice.
  bool? _pro;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(_pro == null ? 'Change player' : _listTitle),
      content: SizedBox(
        width: 360,
        child: _pro == null ? _kindChoice() : _playerList(),
      ),
      actions: [
        if (_pro != null)
          TextButton(
            onPressed: () => setState(() => _pro = null),
            child: const Text('Back'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String get _listTitle => _pro! ? 'Choose a pro' : 'Choose an amateur';

  Widget _kindChoice() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'Is the new player a pro or an amateur?',
        style: TextStyle(color: Colors.white70),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _pro = true),
              child: const Text('Pro'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _pro = false),
              child: const Text('Amateur'),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _playerList() {
    final source = _pro! ? builtInProfiles : homeGameProfiles;
    final available = [...source]
      ..removeWhere((p) => widget.seatedProfileIds.contains(p.id))
      ..sort((a, b) => compareByLastName(a.name, b.name));
    if (available.isEmpty) {
      return const Text(
        'Everyone in this list is already seated.',
        style: TextStyle(color: Colors.white70),
      );
    }
    return SizedBox(
      height: 360,
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: available.length,
        itemBuilder: (context, i) {
          final p = available[i];
          return ListTile(
            title: Text(p.name),
            subtitle: Text(
              p.archetype,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54),
            ),
            onTap: () => Navigator.of(context).pop(p),
          );
        },
      ),
    );
  }
}
