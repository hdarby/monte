import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:monte/core/domain/engine/chip_breakdown.dart';
import 'package:monte/core/presentation/widgets/chip_stack_view.dart';
import 'package:monte/core/theme/app_theme.dart';

/// Fills the screen while a table or tournament field is being built —
/// replaces a bare spinner with cycling status text ("Seating players…",
/// "Collecting buy-ins…") and a small looping animation (cards shuffling,
/// a chip stack growing), so a multi-second setup reads as something
/// happening rather than a stall.
class TableLoadingView extends StatefulWidget {
  const TableLoadingView({super.key, this.messages = defaultMessages});

  final List<String> messages;

  static const defaultMessages = [
    'Shuffling the deck…',
    'Seating players…',
    'Collecting buy-ins…',
    'Racking the chips…',
    'Dealing you in…',
  ];

  @override
  State<TableLoadingView> createState() => _TableLoadingViewState();
}

class _TableLoadingViewState extends State<TableLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _messageIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _cycleMessage();
  }

  void _cycleMessage() {
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(
        () => _messageIndex = (_messageIndex + 1) % widget.messages.length,
      );
      _cycleMessage();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 90,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) =>
                    _ShuffleAndStack(progress: _controller.value),
              ),
            ),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: Text(
                widget.messages[_messageIndex],
                key: ValueKey(_messageIndex),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three cards flipping in a staggered loop beside a chip stack that grows and
/// shrinks — driven entirely by [progress] (0..1, looping) so it never needs
/// its own timers.
class _ShuffleAndStack extends StatelessWidget {
  const _ShuffleAndStack({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    // Chip count breathes between 3 and 12 over the loop.
    final chipCount =
        3 + ((math.sin(progress * 2 * math.pi) + 1) * 4.5).round();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _FlippingCard(phase: (progress + i * 0.18) % 1.0),
          ),
        const SizedBox(width: 24),
        ChipColumnView(
          column: ChipColumn(denomination: 1000, count: chipCount),
          chipWidth: 26,
          chipHeight: 6,
          pitch: 3.2,
        ),
      ],
    );
  }
}

/// A single card that flips edge-on (scaleX through zero) once per loop,
/// showing its back mid-flip.
class _FlippingCard extends StatelessWidget {
  const _FlippingCard({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    // A narrow window of the loop is "mid-flip"; scaleX crosses zero there.
    final flip = math.cos(phase * 2 * math.pi);
    final isBack = flip < 0;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.002)
      ..scaleByDouble(flip.abs().clamp(0.15, 1.0), 1.0, 1.0, 1.0);

    return Transform(
      alignment: Alignment.center,
      transform: transform,
      child: Container(
        width: 30,
        height: 42,
        decoration: BoxDecoration(
          color: isBack ? AppTheme.chip : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black87, width: 1.2),
        ),
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.all(3),
        child: isBack
            ? null
            : const Text(
                '♠',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
      ),
    );
  }
}
