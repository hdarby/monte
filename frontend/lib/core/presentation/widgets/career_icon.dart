import 'package:flutter/material.dart';

/// Icon for "career winnings": an upward trend arrow with a dollar badge — a
/// mashup that reads clearly as "money, going up" at toolbar size, where
/// either icon alone is more ambiguous (a bare $ could be buy-in; a bare
/// arrow could be chip count).
class CareerIcon extends StatelessWidget {
  const CareerIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: const [
          Icon(Icons.trending_up, size: 24, color: Colors.white70),
          Positioned(
            right: -2,
            bottom: -2,
            child: CircleAvatar(
              radius: 7,
              backgroundColor: Colors.black87,
              child: Text(
                r'$',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
