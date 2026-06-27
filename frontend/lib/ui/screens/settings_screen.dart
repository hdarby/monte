import 'package:flutter/material.dart';

import '../../data/local_game_repository.dart';
import '../../settings/game_settings.dart';
import '../../theme/app_theme.dart';

/// Lets the player choose the table size and display units.
///
/// Returns the updated [GameSettings] via [Navigator.pop], or null if dismissed
/// without applying.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});

  final GameSettings settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _count = widget.settings.playerCount;
  late bool _showBigBlinds = widget.settings.showBigBlinds;
  late bool _allBots = widget.settings.allBots;

  String get _countLabel {
    if (_count == 2) return 'Heads-up';
    if (_count == TableConfig.maxPlayers) return 'Full table';
    return '$_count players';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Table Settings'),
        backgroundColor: AppTheme.surface,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Number of players',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('You plus the rest of the seats filled by bots.',
                    style: TextStyle(color: Colors.white60)),
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      Text('$_count',
                          style: const TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.gold,
                            height: 1,
                          )),
                      Text(_countLabel,
                          style: const TextStyle(
                              fontSize: 16, color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.gold,
                    thumbColor: AppTheme.gold,
                    overlayColor: AppTheme.gold.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: _count.toDouble(),
                    min: TableConfig.minPlayers.toDouble(),
                    max: TableConfig.maxPlayers.toDouble(),
                    divisions: TableConfig.maxPlayers - TableConfig.minPlayers,
                    label: '$_count',
                    onChanged: (v) => setState(() => _count = v.round()),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Heads-up (2)',
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                      Text('Full table (10)',
                          style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                const Text('Display amounts',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.gold,
                  value: _showBigBlinds,
                  onChanged: (v) => setState(() => _showBigBlinds = v),
                  title: Text(_showBigBlinds ? 'Big blinds (BB)' : 'Dollars (\$)'),
                  subtitle: Text(
                    _showBigBlinds
                        ? 'Stacks and bets shown as multiples of the big blind.'
                        : 'Stacks and bets shown as actual chip amounts.',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                const Text('Evaluation',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppTheme.gold,
                  value: _allBots,
                  onChanged: (v) => setState(() => _allBots = v),
                  title: const Text('All bots (no human)'),
                  subtitle: const Text(
                    'Every seat is a bot. Watch hands play out, or batch-'
                    'simulate from Analytics, then mine the recorded histories.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16)),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => Navigator.pop(
                          context,
                          GameSettings(
                            playerCount: _count,
                            showBigBlinds: _showBigBlinds,
                            allBots: _allBots,
                          ),
                        ),
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
