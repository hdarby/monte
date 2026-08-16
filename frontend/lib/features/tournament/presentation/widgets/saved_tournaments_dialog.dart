import 'package:flutter/material.dart';

import 'package:monte/core/theme/app_theme.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/data/tournament_save_store.dart';
import 'package:monte/features/tournament/domain/tournament_save.dart';

/// What the player chose to do with a save.
enum SavedTournamentAction { load, deleted }

/// The saved-tournaments browser: pick one, then load or delete it.
///
/// Selection is a separate step from acting on it, deliberately. A list where
/// every row carries its own load and delete buttons puts a destructive control
/// a few pixels from the one you actually want, in a list where every row looks
/// alike.
class SavedTournamentsDialog extends StatefulWidget {
  const SavedTournamentsDialog({super.key, required this.store});

  final TournamentSaveStore store;

  /// Returns the save to load, or null if the player only deleted / cancelled.
  static Future<TournamentSave?> show(
    BuildContext context,
    TournamentSaveStore store,
  ) =>
      showDialog<TournamentSave>(
        context: context,
        builder: (_) => SavedTournamentsDialog(store: store),
      );

  @override
  State<SavedTournamentsDialog> createState() => _SavedTournamentsDialogState();
}

class _SavedTournamentsDialogState extends State<SavedTournamentsDialog> {
  List<TournamentSave>? _saves;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final saves = await widget.store.list();
    if (!mounted) return;
    setState(() {
      _saves = saves;
      // Keep the selection only if it still exists.
      if (!saves.any((s) => s.id == _selectedId)) _selectedId = null;
    });
  }

  TournamentSave? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final s in _saves ?? const <TournamentSave>[]) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final saves = _saves;
    final selected = _selected;

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Saved tournaments'),
      content: SizedBox(
        width: 460,
        height: 340,
        child: saves == null
            ? const Center(child: CircularProgressIndicator())
            : saves.isEmpty
                ? const Center(
                    child: Text(
                      'No saved tournaments yet.\n'
                      'Use the save button during a tournament to keep one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: saves.length,
                    itemBuilder: (context, i) => _row(saves[i]),
                  ),
      ),
      actions: [
        if ((saves ?? const []).isNotEmpty)
          TextButton(
            onPressed: _confirmDeleteAll,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF5350),
            ),
            child: const Text('Delete all'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: selected == null ? null : () => _confirmDelete(selected),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFEF5350),
          ),
          child: const Text('Delete'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: Colors.black,
          ),
          onPressed:
              selected == null ? null : () => Navigator.pop(context, selected),
          child: const Text('Load'),
        ),
      ],
    );
  }

  Widget _row(TournamentSave s) {
    final active = s.players.where((p) => p.status == 'active').length;
    final selected = s.id == _selectedId;
    return Material(
      color: selected ? AppTheme.gold.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        // Selection only. A double-tap-to-load shortcut would be nice, but
        // registering one makes every *single* click wait out the double-tap
        // timeout before it selects, which is a real cost on every interaction
        // for a rarely-used convenience.
        onTap: () => setState(() => _selectedId = s.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: selected ? AppTheme.gold : Colors.white24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${TournamentSave.formatStamp(s.savedAt)}  ·  '
                      'level ${s.levelIndex + 1}  ·  '
                      '$active of ${s.players.length} left  ·  '
                      'pool ${formatChips(s.prizePool)}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(TournamentSave s) async {
    final ok = await _confirm(
      title: 'Delete this save?',
      body: '"${s.name}" from ${TournamentSave.formatStamp(s.savedAt)} will be '
          'permanently deleted. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;
    await widget.store.delete(s.id);
    await _reload();
  }

  Future<void> _confirmDeleteAll() async {
    final n = (_saves ?? const []).length;
    final ok = await _confirm(
      title: 'Delete all saved tournaments?',
      body: 'All $n saved ${n == 1 ? 'tournament' : 'tournaments'} will be '
          'permanently deleted. This cannot be undone.',
      confirmLabel: 'Delete all',
    );
    if (ok != true) return;
    await widget.store.deleteAll();
    await _reload();
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(title),
          content: Text(body),
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
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
}

/// Asks what to call a save, pre-filled with something sensible.
Future<String?> promptForSaveName(
  BuildContext context, {
  required String initial,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Save tournament'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          const SizedBox(height: 10),
          const Text(
            'Saved at the end of the current hand. The hand in progress is not '
            'part of the save — loading deals fresh from these chip counts.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.gold,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
