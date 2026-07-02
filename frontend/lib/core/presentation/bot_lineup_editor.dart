import 'package:flutter/material.dart';

import 'package:monte/core/domain/ai/bot_spec.dart';
import 'package:monte/core/domain/ai/decider_factory.dart';
import 'package:monte/core/domain/ai/personality.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/theme/app_theme.dart';

/// A per-seat bot lineup editor: one row per seat choosing a named **Pro** or a
/// custom **Brain + Personality**, plus a "Set all custom" convenience row.
///
/// Stateless — the parent owns [specs] and gets a fresh list via [onChanged] on
/// every edit. Shared by the New Game dialog and the settings screen so both show
/// the identical control.
class BotLineupEditor extends StatelessWidget {
  const BotLineupEditor({
    super.key,
    required this.seatNames,
    required this.specs,
    required this.onChanged,
  });

  final List<String> seatNames;
  final List<BotSpec> specs;
  final ValueChanged<List<BotSpec>> onChanged;

  void _replace(int i, BotSpec spec) {
    final next = List.of(specs);
    next[i] = spec;
    onChanged(next);
  }

  void _setAllBrains(BotType b) =>
      onChanged([for (final s in specs) s.copyWith(brain: b)]);

  void _setAllStyles(PersonalityArchetype a) =>
      onChanged([for (final s in specs) s.copyWith(style: a)]);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        for (var i = 0; i < specs.length; i++) _seatRow(i),
      ],
    );
  }

  Widget _seatRow(int i) {
    final spec = specs[i];
    final custom = !spec.isProfile;
    final name = i < seatNames.length ? seatNames[i] : 'Bot ${i + 1}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: _ProDropdown(
              value: spec.profile,
              onChanged: (p) => _replace(i, spec.withProfile(p)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _BrainDropdown(
              value: spec.brain,
              enabled: custom, // a named pro defines its own play
              onChanged: (b) => _replace(i, spec.copyWith(brain: b)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StyleDropdown(
              value: spec.style,
              enabled: custom && spec.brain.usesPersonality,
              onChanged: (a) => _replace(i, spec.copyWith(style: a)),
            ),
          ),
        ],
      ),
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
        for (final t in BotType.selectable)
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
