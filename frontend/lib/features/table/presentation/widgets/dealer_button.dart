import 'package:flutter/material.dart';

/// A casino-style dealer button: an ivory disc with a dark outer rim, a thin
/// gold inner ring, and an embossed "D" — not a flat coloured circle.
class DealerButton extends StatelessWidget {
  const DealerButton({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    const ivory = Color(0xFFF5EEDC);
    const ivoryShade = Color(0xFFD9CFB4);
    const rim = Color(0xFF20140A);
    const gold = Color(0xFFC79A3B);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Off-centre highlight gives the disc a subtle domed, 3D feel.
        gradient: const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [Colors.white, ivory, ivoryShade],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: rim, width: size * 0.07),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.66,
          height: size * 0.66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: gold, width: size * 0.045),
          ),
          child: Center(
            child: Text(
              'D',
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w900,
                color: rim,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
