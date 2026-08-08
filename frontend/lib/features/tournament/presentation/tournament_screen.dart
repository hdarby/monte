import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/core/di/game_providers.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// The interactive tournament: the human plays their table live (via the reused
/// [TableScreen]) with a tournament HUD overlaid; other tables simulate between
/// hands. Owns the [TournamentController] lifecycle for the screen.
class TournamentScreen extends ConsumerStatefulWidget {
  const TournamentScreen({
    super.key,
    required this.structure,
    required this.field,
    required this.buyIn,
    required this.tableSize,
    required this.humanName,
  });

  final TournamentStructure structure;

  /// The bot field (one profile per non-human seat), each playing its own
  /// personality. The human takes the remaining seat.
  final List<PlayerProfile> field;
  final int buyIn;
  final int tableSize;
  final String humanName;

  @override
  ConsumerState<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends ConsumerState<TournamentScreen> {
  late final TournamentController _c;
  TableSnapshot? _table;
  TournamentSnapshot? _tour;
  SimProgress? _sim;

  @override
  void initState() {
    super.initState();
    final names = [widget.humanName, ...widget.field.map((p) => p.name)];
    _c = TournamentController.create(
      structure: widget.structure,
      entrants: widget.field.length + 1,
      buyIn: widget.buyIn,
      tableSize: widget.tableSize,
      seed: DateTime.now().millisecondsSinceEpoch % 1000000,
      humanSeat: true,
      names: names,
      botProfiles: widget.field,
      statsService: ref.read(opponentStatsServiceProvider),
    );
    _c.tableStream.listen((s) {
      if (mounted) setState(() => _table = s);
    });
    _c.tournamentStream.listen((s) {
      if (!mounted) return;
      setState(() => _tour = s);
      if (s.colorUp != null) _showColorUp(s.colorUp!);
    });
    _c.simProgressStream.listen((s) {
      if (mounted) setState(() => _sim = s.isRunning ? s : null);
    });
    _c.startLive();
  }

  /// Announces a color-up (chip race): the retired chip and who won/lost what.
  void _showColorUp(ColorUpDisplay c) {
    final gainers = c.rows.where((r) => r.delta != 0).toList();
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Color up: ${_chips(c.retiredUnit)} chips raced off'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Smallest chip in play is now ${_chips(c.newUnit)}.'),
            const SizedBox(height: 12),
            if (gainers.isEmpty)
              const Text('Everyone had exact change — no chips changed hands.')
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260, maxWidth: 320),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final r in gainers)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  r.isHuman ? '${r.name} (you)' : r.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: r.isHuman
                                          ? FontWeight.bold
                                          : FontWeight.normal),
                                ),
                              ),
                              Text(
                                '${r.delta > 0 ? '+' : ''}${_chips(r.delta)}',
                                style: TextStyle(
                                    color: r.delta > 0
                                        ? Colors.green
                                        : Colors.red),
                              ),
                            ],
                          ),
                        ),
                    ],
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
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _noop() {}

  @override
  Widget build(BuildContext context) {
    final table = _table;
    final tour = _tour;
    if (table == null || tour == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // The human's current table size drives the felt layout.
    final playerCount = table.seats.length;

    return Stack(
      children: [
        TableScreen(
          snapshot: table,
          isAllBots: false,
          humanName: widget.humanName,
          playerCount: playerCount,
          sidePanel: _StandingsPanel(rows: _c.standings()),
          readForSeat: _c.readForSeat,
          onAction: _c.submitLiveAction,
          onNewGame: _noop,
          onNextHand: _noop, // hands auto-advance in a tournament
          onOpenSettings: _noop,
          onOpenAnalytics: _noop,
          onOpenHistory: _noop,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
              child: _TournamentHud(
                  tour: tour,
                  standings: _c.standings,
                  humanName: widget.humanName)),
        ),
        if (_sim != null && !tour.finished)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(child: _SimProgressBar(sim: _sim!)),
          ),
        if (tour.finished) _ResultsOverlay(tour: tour),
      ],
    );
  }
}

/// A slim bottom banner shown while the other tables simulate their hand, so the
/// wait reads as progress ("table N of M") rather than an opaque spinner.
class _SimProgressBar extends StatelessWidget {
  const _SimProgressBar({required this.sim});
  final SimProgress sim;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text('Simulating other tables — ${sim.done} of ${sim.total}',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: sim.fraction, minHeight: 4),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact banner showing the tournament state. Every stat is tappable and
/// opens a popup with more detail (e.g. the level chip shows the full blind
/// ladder with the active level highlighted).
class _TournamentHud extends StatelessWidget {
  const _TournamentHud(
      {required this.tour, required this.standings, required this.humanName});
  final TournamentSnapshot tour;
  final String humanName;

  /// Builds the full live standings on demand (see [TournamentController.standings]).
  final List<StandingRow> Function() standings;

  @override
  Widget build(BuildContext context) {
    final clock = tour.clockMode == LevelClockMode.hands
        ? 'hand ${tour.handsThisLevel + 1}/${tour.handsPerLevel}'
        : 'L${tour.level}';
    final ante = tour.ante > 0 ? '+${tour.ante}' : '';
    final nextPay = tour.nextPayoutAmount > 0
        ? '${_ord(tour.nextPayoutPlace)} \$${tour.nextPayoutAmount}'
        : '${_ord(tour.nextPayoutPlace)}=bubble';
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white, fontSize: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _chip(context, 'L${tour.level}',
                  '${tour.smallBlind}/${tour.bigBlind}$ante', _levelDetails),
              _chip(context, 'Left', '${tour.playersLeft}/${tour.entrants}',
                  _fieldDetails),
              _chip(context, 'Avg', '${tour.averageStack}', _stackDetails),
              _chip(context, humanName,
                  '${tour.yourChips} · ${_ord(tour.yourPlace)}', _youDetails),
              _chip(context, 'Pool', '\$${tour.prizePool}', _payoutDetails),
              _chip(context, tour.inMoney ? 'ITM' : 'Next', nextPay,
                  _payoutDetails),
              Text(clock, style: const TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    String value,
    Widget Function() detail,
  ) =>
      InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showDialog<void>(context: context, builder: (_) => detail()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 10)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 2),
                  const Icon(Icons.info_outline, size: 10, color: Colors.white38),
                ],
              ),
            ],
          ),
        ),
      );

  double get _yourBb => tour.bigBlind == 0 ? 0 : tour.yourChips / tour.bigBlind;
  double get _avgBb => tour.bigBlind == 0 ? 0 : tour.averageStack / tour.bigBlind;

  Widget _levelDetails() => _Detail(
        title: 'Blind structure',
        body: SizedBox(
          width: 320,
          height: 360,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Smallest chip in play: ${_chips(tour.smallestChip)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: ListView.builder(
            itemCount: tour.schedule.length,
            itemBuilder: (context, i) {
              final l = tour.schedule[i];
              final active = i == tour.levelIndex;
              final ante = l.ante > 0 ? '  + ${l.ante} ante' : '';
              return Container(
                color: active ? Colors.amber.withValues(alpha: 0.22) : null,
                child: ListTile(
                  dense: true,
                  leading: Text('L${l.level}',
                      style: TextStyle(
                          fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                  title: Text('${l.smallBlind} / ${l.bigBlind}$ante'),
                  trailing: active
                      ? Text(
                          tour.clockMode == LevelClockMode.hands
                              ? 'hand ${tour.handsThisLevel + 1}/${tour.handsPerLevel}'
                              : 'now',
                          style: const TextStyle(color: Colors.amber))
                      : null,
                ),
              );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Widget _fieldDetails() => _Detail(
        title: 'Field',
        body: _rows([
          ('Players left', '${tour.playersLeft} of ${tour.entrants}'),
          ('Busted', '${tour.entrants - tour.playersLeft}'),
          ('Tables', '${tour.tableCount}'),
          ('Places paid', '${tour.paidPlaces}'),
          ('To the money', tour.inMoney
              ? 'in the money'
              : '${tour.playersLeft - tour.paidPlaces} to bust'),
        ]),
      );

  Widget _stackDetails() => _Detail(
        title: 'Stacks',
        body: _rows([
          ('Average stack', '${tour.averageStack}  (${_avgBb.toStringAsFixed(1)} BB)'),
          ('Your stack', '${tour.yourChips}  (${_yourBb.toStringAsFixed(1)} BB)'),
          ('vs average', '${(tour.averageStack == 0 ? 0 : (tour.yourChips / tour.averageStack * 100)).round()}%'),
          ('Total chips', '${tour.totalChips}'),
          ('Starting stack', '${tour.startingStack}'),
        ]),
      );

  Widget _youDetails() => _Detail(
        title: 'Your standing',
        body: SizedBox(
          width: 320,
          height: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _rows([
                ('Chips',
                    '${tour.yourChips}  (${_yourBb.toStringAsFixed(1)} BB)'),
                ('Place', '${_ord(tour.yourPlace)} of ${tour.entrants}'),
                ('If you bust now',
                    tour.nextPayoutAmount > 0
                        ? '${_ord(tour.nextPayoutPlace)} — \$${tour.nextPayoutAmount}'
                        : '${_ord(tour.nextPayoutPlace)} — no cash (bubble)'),
              ]),
              const Divider(),
              Expanded(child: _StandingsList(rows: standings())),
            ],
          ),
        ),
      );

  Widget _payoutDetails() => _Detail(
        title: 'Payouts',
        body: SizedBox(
          width: 300,
          height: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _rows([
                ('Prize pool', '\$${tour.prizePool}'),
                ('Buy-in', '\$${tour.buyIn} x ${tour.entrants}'),
                ('Places paid', '${tour.paidPlaces}'),
              ]),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemExtent: 32,
                  itemCount: tour.payouts.length,
                  itemBuilder: (context, i) {
                    final active = i + 1 == tour.nextPayoutPlace;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_ord(i + 1),
                              style: TextStyle(
                                  fontWeight: active
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: active ? Colors.amber : null)),
                          Text('\$${tour.payouts[i]}'),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Widget _rows(List<(String, String)> items) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (k, v) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(k, style: const TextStyle(color: Colors.white70)),
                  const SizedBox(width: 16),
                  Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
}

/// A small titled dialog wrapper for the HUD detail popups.
class _Detail extends StatelessWidget {
  const _Detail({required this.title, required this.body});
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(title),
        content: body,
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      );
}

/// The end-of-tournament results, shown over the table when it finishes.
class _ResultsOverlay extends StatelessWidget {
  const _ResultsOverlay({required this.tour});
  final TournamentSnapshot tour;

  @override
  Widget build(BuildContext context) {
    final results = tour.finalResults ?? const [];
    final you = results.where((r) => r.isHuman).toList();
    final paid = results.where((r) => r.prize > 0).toList();
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Tournament complete',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  if (you.isNotEmpty)
                    Text(
                      'You finished ${_ord(you.first.place)} of ${tour.entrants}'
                      '${you.first.prize > 0 ? ' for \$${you.first.prize}' : ''}.',
                      style: const TextStyle(color: Colors.amber),
                    ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemExtent: 44,
                        itemCount: paid.length,
                        itemBuilder: (context, i) {
                          final r = paid[i];
                          return ListTile(
                            dense: true,
                            tileColor: r.isHuman
                                ? Colors.amber.withValues(alpha: 0.18)
                                : null,
                            leading: Text(_ord(r.place)),
                            title: Text(r.name + (r.isHuman ? '  (you)' : '')),
                            trailing: Text('\$${r.prize}'),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to lobby'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tournament standings shown in place of the hand log: a boxed, titled
/// panel wrapping the scrollable standings list (auto-centered on the human).
class _StandingsPanel extends StatelessWidget {
  const _StandingsPanel({required this.rows});
  final List<StandingRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 16, top: 16, bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STANDINGS · ${rows.length}',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(child: _StandingsList(rows: rows)),
        ],
      ),
    );
  }
}

/// A lazy, scrollable standings list (handles thousands of entries) that opens
/// scrolled to center the human's row.
class _StandingsList extends StatefulWidget {
  const _StandingsList({required this.rows});
  final List<StandingRow> rows;

  @override
  State<_StandingsList> createState() => _StandingsListState();
}

class _StandingsListState extends State<_StandingsList> {
  static const double _itemExtent = 24;
  late final ScrollController _controller;
  int _lastCenteredIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnYou());
  }

  @override
  void didUpdateWidget(covariant _StandingsList old) {
    super.didUpdateWidget(old);
    // Re-center whenever the player's position in the standings changes (chips
    // shift, players bust), smoothly following them — but don't fight the user's
    // manual scrolling when their rank is unchanged.
    final i = widget.rows.indexWhere((r) => r.isHuman);
    if (i != _lastCenteredIndex) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _centerOnYou(animate: true));
    }
  }

  void _centerOnYou({bool animate = false}) {
    if (!_controller.hasClients) return;
    final i = widget.rows.indexWhere((r) => r.isHuman);
    if (i < 0) return;
    _lastCenteredIndex = i;
    final pos = _controller.position;
    final target = (i * _itemExtent - (pos.viewportDimension - _itemExtent) / 2)
        .clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _controller.animateTo(target,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } else {
      _controller.jumpTo(target);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemExtent: _itemExtent,
      itemCount: widget.rows.length,
      itemBuilder: (context, i) {
        final r = widget.rows[i];
        final trailing = r.busted
            ? (r.prize > 0 ? 'out·\$${r.prize}' : 'out')
            : _chips(r.chips);
        // Subtle brain tint: blue behind amateurs, red behind pros, amber for
        // the human. Busted rows fade. The human's tint wins over the kind tint.
        // Real, explicitly-chosen personalities get a stronger tint than the
        // anonymous generated fillers of the same kind, so they stand out.
        final amateurA = r.generated ? 0.10 : 0.24;
        final proA = r.generated ? 0.09 : 0.22;
        final Color? tint = r.busted
            ? Colors.black.withValues(alpha: 0.03)
            : r.isHuman
                ? Colors.amber.withValues(alpha: 0.22)
                : switch (r.kind) {
                    StandingKind.amateur =>
                      Colors.blue.withValues(alpha: amateurA),
                    StandingKind.pro => Colors.red.withValues(alpha: proA),
                    StandingKind.human => null,
                  };
        final weight = r.isHuman ? FontWeight.bold : FontWeight.w400;
        final color = r.busted ? Colors.grey : Colors.white;
        return Container(
          color: tint,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text('${r.place}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                        fontSize: 9, fontWeight: weight, color: color)),
              ),
              Expanded(
                child: Text(
                  r.isHuman ? '${_shortName(r.name)} (you)' : _shortName(r.name),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: weight,
                      color: color,
                      decoration:
                          r.busted ? TextDecoration.lineThrough : null),
                ),
              ),
              const SizedBox(width: 4),
              // The chip stack can be large; let it take the room it needs and
              // shrink only if it truly must, so it never clips.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 84),
                child: Text(trailing,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.visible,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: weight,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Abbreviates a full name to "F. Lastname" (matching the seat display), so the
/// narrow standings panel never has to ellipsize. Single-word names pass through.
String _shortName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts.first.isNotEmpty) {
    return '${parts.first[0]}. ${parts.last}';
  }
  return name.trim();
}

/// Formats a chip count with thousands separators, preserving a leading sign.
String _chips(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

String _ord(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
