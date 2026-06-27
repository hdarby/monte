import 'package:flutter/material.dart';

import 'package:poker_client/core/domain/engine/actions.dart';
import 'package:poker_client/core/presentation/money_format.dart';
import 'package:poker_client/core/theme/app_theme.dart';
import 'package:poker_client/features/table/domain/table_snapshot.dart';

/// The bottom control strip: betting actions on the human's turn, otherwise a
/// status line or the "next hand" controls. Reports intents via callbacks.
class ActionBar extends StatefulWidget {
  const ActionBar({
    super.key,
    required this.snapshot,
    required this.onAction,
    required this.onNewGame,
    required this.onNextHand,
  });

  final TableSnapshot snapshot;
  final ValueChanged<GameAction> onAction;
  final VoidCallback onNewGame;
  final VoidCallback onNextHand;

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
    final money = MoneyScope.of(context);
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
                    Row(
                      children: [
                        Text(
                          '${isBet ? 'Bet' : 'Raise to'}: '
                          '${money.format(raiseTo.round())}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.gold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Pot ${money.format(widget.snapshot.pot)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _PresetChip(
                          label: '¼ Pot',
                          onTap: () => _setFraction(ctx, 0.25),
                        ),
                        _PresetChip(
                          label: '½ Pot',
                          onTap: () => _setFraction(ctx, 0.5),
                        ),
                        _PresetChip(
                          label: '¾ Pot',
                          onTap: () => _setFraction(ctx, 0.75),
                        ),
                        _PresetChip(
                          label: 'Pot',
                          onTap: () => _setFraction(ctx, 1.0),
                        ),
                        _PresetChip(
                          label: 'All-In',
                          accent: true,
                          onTap: () => _setRaiseTo(ctx, max),
                        ),
                      ],
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
                    color: Colors.white70,
                  ),
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
          label: ctx.canCheck
              ? 'Check'
              : 'Call ${money.format(ctx.callAmount)}',
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
                  _send(
                    isBet ? GameAction.bet(amount) : GameAction.raise(amount),
                  );
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
          onPressed: widget.onNewGame,
        ),
        const SizedBox(width: 12),
        _ActionButton(
          label: 'Deal Next Hand',
          color: AppTheme.gold,
          foreground: Colors.black,
          enabled: true,
          onPressed: widget.onNextHand,
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

  /// Sets the raise target to a fraction of the pot above the current bet,
  /// clamped to the legal range.
  void _setFraction(ActionContext ctx, double fraction) {
    final target = ctx.currentBet + widget.snapshot.pot * fraction;
    _setRaiseTo(ctx, target);
  }

  void _setRaiseTo(ActionContext ctx, double target) {
    final clamped = target.clamp(
      ctx.minRaiseTo.toDouble(),
      ctx.maxRaiseTo.toDouble(),
    );
    setState(() => _raiseTo = clamped);
  }

  void _send(GameAction action) {
    setState(() => _raiseTo = null);
    widget.onAction(action);
  }
}

/// A compact bet-sizing preset (¼/½/¾/full pot, All-in).
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent
          ? AppTheme.chip.withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}
