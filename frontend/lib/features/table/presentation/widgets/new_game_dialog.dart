import 'package:flutter/material.dart';

import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
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
  late final List<BotSpec> _specs = List.of(widget.initial);

  void _setAllBrains(BotType b) => setState(() {
    for (var i = 0; i < _specs.length; i++) {
      _specs[i] = _specs[i].copyWith(brain: b);
    }
  });

  void _setAllStyles(PersonalityArchetype a) => setState(() {
    for (var i = 0; i < _specs.length; i++) {
      _specs[i] = _specs[i].copyWith(style: a);
    }
  });

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
              'stat-calibrated player, or a custom Brain + Personality '
              '(the Heuristic brain ignores personality).',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            _SetAllRow(onBrain: _setAllBrains, onStyle: _setAllStyles),
            const Divider(color: Colors.white12, height: 24),
            const Row(
              children: [
                SizedBox(width: 80, child: _Head('Seat')),
                Expanded(child: _Head('Pro')),
                SizedBox(width: 12),
                Expanded(child: _Head('Brain')),
                SizedBox(width: 12),
                Expanded(child: _Head('Personality')),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _specs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final spec = _specs[i];
                  final custom = !spec.isProfile;
                  return Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: Text(
                          widget.seatNames[i],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        child: _ProDropdown(
                          value: spec.profile,
                          onChanged: (p) => setState(
                            () => _specs[i] = spec.withProfile(p),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BrainDropdown(
                          value: spec.brain,
                          // A named pro defines its own play.
                          enabled: custom,
                          onChanged: (b) => setState(
                            () => _specs[i] = spec.copyWith(brain: b),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StyleDropdown(
                          value: spec.style,
                          // Disabled for pros and for the fixed heuristic.
                          enabled: custom && spec.brain.usesPersonality,
                          onChanged: (a) => setState(
                            () => _specs[i] = spec.copyWith(style: a),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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

class _SetAllRow extends StatelessWidget {
  const _SetAllRow({required this.onBrain, required this.onStyle});

  final ValueChanged<BotType> onBrain;
  final ValueChanged<PersonalityArchetype> onStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Set all custom:',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _BrainDropdown(
            value: null,
            hint: 'Brain…',
            onChanged: (b) => onBrain(b!),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StyleDropdown(
            value: null,
            hint: 'Personality…',
            onChanged: (a) => onStyle(a!),
          ),
        ),
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: Colors.white38,
      fontSize: 11,
      letterSpacing: 1.2,
      fontWeight: FontWeight.bold,
    ),
  );
}

class _ProDropdown extends StatelessWidget {
  const _ProDropdown({required this.value, required this.onChanged});

  final PlayerProfile? value;
  final ValueChanged<PlayerProfile?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<PlayerProfile?>(
      value: value,
      isExpanded: true,
      dropdownColor: AppTheme.surface,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: [
        const DropdownMenuItem<PlayerProfile?>(
          child: Text('— Custom —', style: TextStyle(fontSize: 14)),
        ),
        for (final p in builtInProfiles)
          DropdownMenuItem<PlayerProfile?>(
            value: p,
            child: Text(p.name, style: const TextStyle(fontSize: 14)),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _BrainDropdown extends StatelessWidget {
  const _BrainDropdown({
    required this.value,
    required this.onChanged,
    this.hint,
    this.enabled = true,
  });

  final BotType? value;
  final ValueChanged<BotType?> onChanged;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<BotType>(
      value: value,
      isExpanded: true,
      hint: hint == null
          ? null
          : Text(hint!, style: const TextStyle(fontSize: 14)),
      dropdownColor: AppTheme.surface,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: [
        for (final t in BotType.values)
          DropdownMenuItem(value: t, child: Text(t.shortLabel)),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _StyleDropdown extends StatelessWidget {
  const _StyleDropdown({
    required this.value,
    required this.onChanged,
    this.hint,
    this.enabled = true,
  });

  final PersonalityArchetype? value;
  final ValueChanged<PersonalityArchetype?> onChanged;
  final String? hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<PersonalityArchetype>(
      value: value,
      isExpanded: true,
      hint: hint == null
          ? null
          : Text(hint!, style: const TextStyle(fontSize: 14)),
      dropdownColor: AppTheme.surface,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: [
        for (final a in PersonalityArchetype.values)
          DropdownMenuItem(value: a, child: Text(a.label)),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
