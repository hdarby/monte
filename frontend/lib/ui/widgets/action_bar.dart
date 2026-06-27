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
    final canRaise = ctx.canRaise;
    final min = ctx.minRaiseTo.toDouble();
    final max = ctx.maxRaiseTo.toDouble();
    final raiseTo = canRaise ? (_raiseTo ?? min).clamp(min, max) : min;
    final isBet = ctx.currentBet == 0;

    return _bar(
      children: [
        Expanded(
          child: canRaise
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${isBet ? 'Bet' : 'Raise to'}: ${raiseTo.round()}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppTheme.gold,
                        thumbColor: AppTheme.gold,
                        overlayColor: AppTheme.gold.withValues(alpha: 0.2),
                      ),
                      child: Slider(
                        value: raiseTo.toDouble(),
                        min: min,
                        max: max,
                        onChanged: max > min
                            ? (v) => setState(() => _raiseTo = v)
                            : null,
                      ),
                    ),
                  ],
                )
              : const Text(
                  'Your move',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.white70),
                ),
        ),
        const SizedBox(width: 16),
        _ActionButton(
          label: 'Fold',
          color: const Color(0xFFC0392B),
          enabled: true,
          onPressed: () => _send(const GameAction.fold()),
        ),
        const SizedBox(width: 12),
        _ActionButton(
          label: ctx.canCheck ? 'Check' : 'Call ${ctx.callAmount}',
          color: const Color(0xFF27AE60),
          enabled: true,
          onPressed: () => _send(
            ctx.canCheck ? const GameAction.check() : const GameAction.call(),
          ),
        ),
        const SizedBox(width: 12),
        _ActionButton(
          label: isBet ? 'Bet' : 'Raise',
          color: AppTheme.gold,
          foreground: Colors.black,
          enabled: canRaise,
          onPressed: canRaise
              ? () {
                  final amount = raiseTo.round();
                  _send(isBet ? GameAction.bet(amount) : GameAction.raise(amount));
                }
              : null,
        ),
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
        _ActionButton(
          label: 'New Game',
          color: const Color(0xFF4A6572),
          enabled: true,
          onPressed: () => widget.repository.newGame(),
        ),
        const SizedBox(width: 12),
        _ActionButton(
          label: 'Deal Next Hand',
          color: AppTheme.gold,
          foreground: Colors.black,
          enabled: true,
          onPressed: () => widget.repository.startNextHand(),
        ),
      ],
    );
  }

  Widget _waiting() => _bar(
        children: const [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Waiting for opponents…', style: TextStyle(fontSize: 15)),
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

/// A betting button with a vivid enabled state and an obviously-greyed disabled
/// state, so the player can always tell what's available.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onPressed,
    this.foreground = Colors.white,
  });

  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback? onPressed;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: foreground,
          disabledBackgroundColor: const Color(0xFF2A332C),
          disabledForegroundColor: Colors.white24,
          elevation: enabled ? 3 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}
