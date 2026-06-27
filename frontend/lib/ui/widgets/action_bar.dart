import 'package:flutter/material.dart';

import '../../data/game_repository.dart';
import '../../data/table_snapshot.dart';
import '../../engine/actions.dart';
import '../../theme/app_theme.dart';

/// The bottom control strip: betting actions on the human's turn, otherwise a
/// status line or the "next hand" controls.
class ActionBar extends StatefulWidget {
  const ActionBar({
    super.key,
    required this.snapshot,
    required this.repository,
  });

  final TableSnapshot snapshot;
  final GameRepository repository;

  @override
  State<ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<ActionBar> {
  double? _raiseTo;

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;

    if (snap.isHandOver) return _endOfHandControls();
    final ctx = snap.actionContext;
    if (ctx == null) return _waiting();

    return _actions(ctx);
  }

  Widget _actions(ActionContext ctx) {
    final min = ctx.minRaiseTo.toDouble();
    final max = ctx.maxRaiseTo.toDouble();
    final raiseTo = (_raiseTo ?? min).clamp(min, max);
    final isBet = ctx.currentBet == 0;

    return _bar(
      children: [
        if (ctx.canRaise) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${isBet ? 'Bet' : 'Raise to'}: ${raiseTo.round()}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Slider(
                  value: raiseTo.toDouble(),
                  min: min,
                  max: max,
                  activeColor: AppTheme.gold,
                  onChanged: max > min
                      ? (v) => setState(() => _raiseTo = v)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey),
          onPressed: () => _send(const GameAction.fold()),
          child: const Text('Fold'),
        ),
        const SizedBox(width: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.feltDark),
          onPressed: () => _send(
            ctx.canCheck ? const GameAction.check() : const GameAction.call(),
          ),
          child: Text(ctx.canCheck ? 'Check' : 'Call ${ctx.callAmount}'),
        ),
        if (ctx.canRaise) ...[
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.chip),
            onPressed: () {
              final amount = raiseTo.round();
              _send(isBet
                  ? GameAction.bet(amount)
                  : GameAction.raise(amount));
            },
            child: Text(isBet ? 'Bet' : 'Raise'),
          ),
        ],
      ],
    );
  }

  Widget _endOfHandControls() {
    return _bar(
      children: [
        const Expanded(
          child: Text(
            'Hand complete',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey),
          onPressed: () => widget.repository.newGame(),
          child: const Text('New Game'),
        ),
        const SizedBox(width: 10),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.gold,
              foregroundColor: Colors.black),
          onPressed: () => widget.repository.startNextHand(),
          child: const Text('Deal Next Hand'),
        ),
      ],
    );
  }

  Widget _waiting() => _bar(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Waiting for opponents…',
                  style: TextStyle(fontSize: 15)),
            ],
          ),
        ],
      );

  Widget _bar({required List<Widget> children}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: Row(children: children),
      );

  void _send(GameAction action) {
    setState(() => _raiseTo = null);
    widget.repository.submitAction(action);
  }
}
