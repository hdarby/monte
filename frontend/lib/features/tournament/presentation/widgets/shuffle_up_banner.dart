import 'package:flutter/material.dart';

/// A full-screen scrim shown once at the start of a fresh tournament, over
/// an already-dealt-and-waiting first hand, until the player taps through.
/// The banner zooms in with an elastic overshoot, reveals letter by letter,
/// and cycles color continuously while it's on screen.
class ShuffleUpBanner extends StatefulWidget {
  const ShuffleUpBanner({super.key, required this.onOk});
  final VoidCallback onOk;

  @override
  State<ShuffleUpBanner> createState() => _ShuffleUpBannerState();
}

class _ShuffleUpBannerState extends State<ShuffleUpBanner>
    with TickerProviderStateMixin {
  static const _text = 'Shuffle Up and Deal!';

  // One-shot: drives the zoom-in pop and the letter-by-letter reveal.
  late final AnimationController _entrance = AnimationController(
    duration: const Duration(milliseconds: 1400),
    vsync: this,
  )..forward();

  // Repeats for as long as the banner is on screen: continuous color cycling.
  late final AnimationController _colorCycle = AnimationController(
    duration: const Duration(seconds: 3),
    vsync: this,
  )..repeat();

  late final Animation<double> _zoom = CurvedAnimation(
    parent: _entrance,
    curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
  );

  @override
  void dispose() {
    _entrance.dispose();
    _colorCycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.88),
    child: Center(
      child: AnimatedBuilder(
        animation: _zoom,
        builder: (context, child) =>
            Transform.scale(scale: 0.4 + 0.6 * _zoom.value, child: child),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_entrance, _colorCycle]),
              builder: (context, _) => Wrap(
                alignment: WrapAlignment.center,
                children: [for (var i = 0; i < _text.length; i++) _letter(i)],
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: widget.onOk,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Text('OK'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// One character of the banner: revealed (fade + slight rise) on its own
  /// slice of [_entrance]'s timeline, staggered across all the letters, and
  /// colored from a continuously-rotating hue (offset per letter so the
  /// cycling reads as a wave across the text, not one flat flashing color).
  Widget _letter(int i) {
    final n = _text.length;
    final start = 0.15 + 0.75 * (i / n);
    final end = (start + 0.25).clamp(0.0, 1.0);
    final reveal = Interval(
      start,
      end,
      curve: Curves.easeOut,
    ).transform(_entrance.value);
    final hue = (_colorCycle.value * 360 + i * 14) % 360;
    final color = HSVColor.fromAHSV(1.0, hue, 0.55, 1.0).toColor();
    final ch = _text[i];
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, (1 - reveal) * 10),
        child: Text(
          ch == ' ' ? ' ' : ch,
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
