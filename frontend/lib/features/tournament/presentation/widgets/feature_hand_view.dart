import 'package:flutter/material.dart';
import 'package:monte/core/domain/engine/actions.dart';
import 'package:monte/core/util/format.dart';
import 'package:monte/features/tournament/domain/tournament_chronicle.dart';

/// Renders a replayed hand the way a broadcast would call it: a roster of who
/// saw the flop (position, cards, stack in big blinds), then each street —
/// board, what happened, and Bart's read — followed by his closing take and a
/// verdict on every player.
class FeatureHandView extends StatelessWidget {
  const FeatureHandView({
    super.key,
    required this.hand,
    required this.bigBlind,
  });

  final HandReplay hand;
  final int bigBlind;

  int get _bb => hand.bigBlind > 0 ? hand.bigBlind : bigBlind;

  @override
  Widget build(BuildContext context) {
    final gold = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PotHeader(pot: hand.pot, bigBlind: _bb, gold: gold),
        const SizedBox(height: 8),

        // Who saw the flop.
        for (final seat in hand.seats)
          _RosterRow(seat: seat, bigBlind: _bb, gold: gold),

        // Street by street: what happened, then the read on it.
        for (final street in hand.streets)
          _StreetBlock(street: street, bigBlind: _bb, gold: gold),

        // The closing take.
        if (hand.commentary.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SectionRule(gold: gold, label: "BART'S TAKE"),
          for (final line in hand.commentary) _Commentary(line, gold: gold),
        ],

        // A word on each player.
        if (hand.verdicts.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final v in hand.verdicts) _VerdictRow(verdict: v),
        ],
      ],
    );
  }
}

/// The pot the hand was played for, in chips and big blinds.
class _PotHeader extends StatelessWidget {
  const _PotHeader({
    required this.pot,
    required this.bigBlind,
    required this.gold,
  });

  final int pot;
  final int bigBlind;
  final Color gold;

  @override
  Widget build(BuildContext context) => Text(
    '${formatChipsWithBb(pot, bigBlind)} pot',
    style: TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.bold),
  );
}

/// One player in the roster: position badge, name, cards, stack in BB.
class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.seat,
    required this.bigBlind,
    required this.gold,
  });

  final ReplaySeat seat;
  final int bigBlind;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final stack = seat.stackBb(bigBlind);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _PositionBadge(label: seat.position.label),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              seat.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: seat.won ? FontWeight.bold : FontWeight.normal,
                color: seat.won ? gold : Colors.white,
              ),
            ),
          ),
          for (final c in seat.cards) MiniCard(code: c),
          const SizedBox(width: 8),
          SizedBox(
            width: 46,
            child: Text(
              '${stack.round()}bb',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// The short position badge (BTN, CO, BB…).
class _PositionBadge extends StatelessWidget {
  const _PositionBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    padding: const EdgeInsets.symmetric(vertical: 1),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 9,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    ),
  );
}

/// One street: the board as it stood, the action in a single line, then Bart.
class _StreetBlock extends StatelessWidget {
  const _StreetBlock({
    required this.street,
    required this.bigBlind,
    required this.gold,
  });

  final ReplayStreet street;
  final int bigBlind;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final action = _actionLine(street, bigBlind);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                street.name.toUpperCase(),
                style: TextStyle(
                  color: gold.withValues(alpha: 0.75),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 6),
              for (final c in street.boardAfter) MiniCard(code: c),
              const Spacer(),
              Text(
                'pot ${_bb(street.potAfter, bigBlind)}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                action,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: Colors.white70,
                ),
              ),
            ),
          for (final line in street.commentary) _Commentary(line, gold: gold),
        ],
      ),
    );
  }

  /// Condenses the street's action into one readable sentence, with sizes in
  /// big blinds: "Ann raises to 2.5bb, Chen calls, Bob folds".
  static String? _actionLine(ReplayStreet street, int bigBlind) {
    if (street.actions.isEmpty) return null;
    final parts = [
      for (final a in street.actions) _describe(a, bigBlind),
    ];
    return parts.join(', ');
  }

  static String _describe(ReplayAction a, int bigBlind) => switch (a.type) {
    ActionType.fold => '${a.name} folds',
    ActionType.check => '${a.name} checks',
    ActionType.call => '${a.name} calls',
    ActionType.bet => '${a.name} bets ${_bb(a.amount, bigBlind)}',
    ActionType.raise => '${a.name} raises to ${_bb(a.amount, bigBlind)}',
    ActionType.allIn => '${a.name} is all in for ${_bb(a.amount, bigBlind)}',
  };

  static String _bb(int chips, int bigBlind) {
    if (bigBlind <= 0) return formatChips(chips);
    final v = chips / bigBlind;
    return v >= 10
        ? '${v.round()}bb'
        : '${v.toStringAsFixed(1).replaceAll('.0', '')}bb';
  }
}

/// A line of Bart's commentary.
class _Commentary extends StatelessWidget {
  const _Commentary(this.text, {required this.gold});
  final String text;
  final Color gold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, left: 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: gold,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

/// A labelled divider introducing the closing sections.
class _SectionRule extends StatelessWidget {
  const _SectionRule({required this.gold, required this.label});
  final Color gold;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Text(
      label,
      style: TextStyle(
        color: gold,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    ),
  );
}

/// Bart's one-line verdict on a player, colour-coded by grade.
class _VerdictRow extends StatelessWidget {
  const _VerdictRow({required this.verdict});
  final PlayerVerdict verdict;

  static const _colors = {
    VerdictGrade.excellent: Color(0xFF66BB6A),
    VerdictGrade.good: Color(0xFF9CCC65),
    VerdictGrade.standard: Colors.white70,
    VerdictGrade.questionable: Color(0xFFFFB74D),
    VerdictGrade.poor: Color(0xFFEF5350),
    VerdictGrade.unlucky: Color(0xFF4FC3F7),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[verdict.grade] ?? Colors.white70;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, height: 1.3),
          children: [
            TextSpan(
              text: '${verdict.name} (${verdict.position.label}) ',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: verdict.line,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small suit-coloured card chip, e.g. A♥, for inline use in recap text.
class MiniCard extends StatelessWidget {
  const MiniCard({super.key, required this.code});

  /// A card code such as `"Ah"` or `"Ts"`.
  final String code;

  @override
  Widget build(BuildContext context) {
    if (code.length < 2) return const SizedBox.shrink();
    final rank = code.substring(0, code.length - 1);
    final (sym, red) = switch (code[code.length - 1].toLowerCase()) {
      'h' => ('♥', true),
      'd' => ('♦', true),
      's' => ('♠', false),
      _ => ('♣', false),
    };
    return Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '$rank$sym',
        style: TextStyle(
          color: red ? Colors.red.shade700 : Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
