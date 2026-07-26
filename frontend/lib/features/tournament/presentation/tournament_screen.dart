import 'package:flutter/material.dart';
import 'package:monte/features/table/domain/table_snapshot.dart';
import 'package:monte/features/table/presentation/table_screen.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_snapshot.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

/// The interactive tournament: the human plays their table live (via the reused
/// [TableScreen]) with a tournament HUD overlaid; other tables simulate between
/// hands. Owns the [TournamentController] lifecycle for the screen.
class TournamentScreen extends StatefulWidget {
  const TournamentScreen({
    super.key,
    required this.structure,
    required this.entrants,
    required this.buyIn,
    required this.tableSize,
    required this.humanName,
  });

  final TournamentStructure structure;
  final int entrants;
  final int buyIn;
  final int tableSize;
  final String humanName;

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  late final TournamentController _c;
  TableSnapshot? _table;
  TournamentSnapshot? _tour;

  @override
  void initState() {
    super.initState();
    final names = [
      widget.humanName,
      ..._botNames.take(widget.entrants - 1),
    ];
    _c = TournamentController.create(
      structure: widget.structure,
      entrants: widget.entrants,
      buyIn: widget.buyIn,
      tableSize: widget.tableSize,
      seed: DateTime.now().millisecondsSinceEpoch % 1000000,
      humanSeat: true,
      names: names,
    );
    _c.tableStream.listen((s) {
      if (mounted) setState(() => _table = s);
    });
    _c.tournamentStream.listen((s) {
      if (mounted) setState(() => _tour = s);
    });
    _c.startLive();
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
          playerCount: playerCount,
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
          child: SafeArea(child: _TournamentHud(tour: tour)),
        ),
        if (tour.finished) _ResultsOverlay(tour: tour),
      ],
    );
  }
}

/// A compact banner showing the tournament state. Every stat is tappable and
/// opens a popup with more detail (e.g. the level chip shows the full blind
/// ladder with the active level highlighted).
class _TournamentHud extends StatelessWidget {
  const _TournamentHud({required this.tour});
  final TournamentSnapshot tour;

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
              _chip(context, 'You', '${tour.yourChips} · ${_ord(tour.yourPlace)}',
                  _youDetails),
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
        body: _rows([
          ('Chips', '${tour.yourChips}  (${_yourBb.toStringAsFixed(1)} BB)'),
          ('Place', '${_ord(tour.yourPlace)} of ${tour.entrants}'),
          ('If you bust now',
              tour.nextPayoutAmount > 0
                  ? '${_ord(tour.nextPayoutPlace)} — \$${tour.nextPayoutAmount}'
                  : '${_ord(tour.nextPayoutPlace)} — no cash (bubble)'),
          ('Money bubble', tour.inMoney
              ? 'in the money'
              : '${tour.playersLeft - tour.paidPlaces} bust-outs away'),
        ]),
      );

  Widget _payoutDetails() => _Detail(
        title: 'Payouts',
        body: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _rows([
                ('Prize pool', '\$${tour.prizePool}'),
                ('Buy-in', '\$${tour.buyIn} x ${tour.entrants}'),
                ('Places paid', '${tour.paidPlaces}'),
              ]),
              const Divider(),
              for (var i = 0; i < tour.payouts.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_ord(i + 1),
                          style: TextStyle(
                              fontWeight: i + 1 == tour.nextPayoutPlace
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: i + 1 == tour.nextPayoutPlace
                                  ? Colors.amber
                                  : null)),
                      Text('\$${tour.payouts[i]}'),
                    ],
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
                  ...results.where((r) => r.prize > 0).map((r) => ListTile(
                        dense: true,
                        leading: Text(_ord(r.place)),
                        title: Text(r.name +
                            (r.isHuman ? '  (you)' : '')),
                        trailing: Text('\$${r.prize}'),
                      )),
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

String _ord(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

const _botNames = [
  'Ivan', 'Mai', 'Rex', 'Lena', 'Oto', 'Priya', 'Dana', 'Kojo', 'Sven', 'Nia',
  'Bo', 'Ada', 'Ren', 'Fay', 'Gus', 'Hana', 'Ivo', 'Zara', 'Cy', 'Wen', 'Tao',
  'Uma', 'Vik', 'Yao', 'Ash', 'Bex', 'Cru', 'Dex', 'Eli', 'Fox', 'Gia', 'Hux',
  'Ines', 'Jax', 'Kit', 'Lux', 'Moe', 'Noa', 'Ozzy', 'Pax', 'Qui', 'Rue', 'Sol',
  'Tex', 'Ubo', 'Val',
];
