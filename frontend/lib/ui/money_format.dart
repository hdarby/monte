import 'package:flutter/widgets.dart';

/// Formats chip amounts either as dollars ("$1000") or big blinds ("100 BB").
class MoneyFormat {
  const MoneyFormat({this.showBigBlinds = false, this.bigBlind = 10});

  final bool showBigBlinds;
  final int bigBlind;

  String format(int chips) {
    if (!showBigBlinds) return '\$$chips';
    final bb = chips / bigBlind;
    final text =
        bb % 1 == 0 ? bb.toStringAsFixed(0) : bb.toStringAsFixed(1);
    return '$text BB';
  }
}

/// Provides the active [MoneyFormat] to the widget subtree. Widgets read it via
/// [MoneyScope.of]; if no scope is present, a default dollar formatter is used,
/// which keeps widgets renderable in isolation (e.g. in tests).
class MoneyScope extends InheritedWidget {
  const MoneyScope({super.key, required this.format, required super.child});

  final MoneyFormat format;

  static MoneyFormat of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MoneyScope>()?.format ??
      const MoneyFormat();

  @override
  bool updateShouldNotify(MoneyScope oldWidget) =>
      oldWidget.format.showBigBlinds != format.showBigBlinds ||
      oldWidget.format.bigBlind != format.bigBlind;
}
