import 'package:flutter/material.dart';

/// Centralised colours and theme for the poker table.
class AppTheme {
  static const felt = Color(0xFF35654D);
  static const feltDark = Color(0xFF234A38);
  static const feltEdge = Color(0xFF6B4423);
  static const gold = Color(0xFFE6B655);
  static const chip = Color(0xFFE63946);
  static const surface = Color(0xFF1B2A22);

  /// Escalating bet-indicator colours by raise level: blinds/limps keep the
  /// neutral [feltEdge]; the initial raise is [betYellow]; a 3-bet warns in
  /// [warnOrange]; a 4-bet+ alarms in [alarmRed]. Calls take their level's colour.
  static const betYellow = Color(0xFFEBC233);
  static const warnOrange = Color(0xFFE8811E);
  static const alarmRed = Color(0xFFD32F2F);

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: surface,
      colorScheme: base.colorScheme.copyWith(
        primary: gold,
        secondary: chip,
        surface: surface,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'Roboto',
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
