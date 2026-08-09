import 'package:flutter/material.dart';
import 'package:monte/core/domain/ai/player_profile.dart';

/// Small building blocks shared by the tournament lobby's option rows.

/// A titled row of single-select chips, e.g. "Field size · 6 / 9 / 80 / …".
class LobbyChoiceRow<T> extends StatelessWidget {
  const LobbyChoiceRow({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  final String title;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LobbyLabel(title),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(labelOf(o)),
              selected: o == selected,
              onSelected: (_) => onSelect(o),
            ),
        ],
      ),
    ],
  );
}

/// A section title in the lobby form.
class LobbyLabel extends StatelessWidget {
  const LobbyLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// A header separating the recreational and pro pools in the player list.
class LobbySectionHeader extends StatelessWidget {
  const LobbySectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );
}

/// One selectable personality in the field list.
class LobbyPlayerTile extends StatelessWidget {
  const LobbyPlayerTile({
    super.key,
    required this.profile,
    required this.selected,
    required this.onChanged,
  });

  final PlayerProfile profile;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    dense: true,
    value: selected,
    onChanged: (v) => onChanged(v ?? false),
    title: Text(profile.name),
    subtitle: Text(
      profile.archetype.replaceAll('_', ' '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
