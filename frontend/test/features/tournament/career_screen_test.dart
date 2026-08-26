import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:monte/features/tournament/data/tournament_result_store.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';
import 'package:monte/features/tournament/presentation/career_screen.dart';

/// An in-memory store, so the screen can be tested without touching disk.
class _FakeStore implements TournamentResultStore {
  _FakeStore(this.results);
  final List<TournamentResult> results;

  @override
  void record(TournamentResult result) => results.add(result);
  @override
  Future<List<TournamentResult>> loadAll() async => results;
  @override
  Future<void> wipe() async => results.clear();
}

TournamentResult _event(List<(String, String, int, int, bool)> f) =>
    TournamentResult(
      timestampMs: 1,
      structureName: 'Turbo',
      buyIn: 100,
      entrants: f.length,
      finishes: [
        for (final (id, name, place, prize, isHuman) in f)
          TournamentFinish(
            profileId: id,
            name: name,
            place: place,
            prize: prize,
            isHuman: isHuman,
          ),
      ],
    );

Future<void> _pump(WidgetTester tester, List<TournamentResult> results) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentResultStoreProvider.overrideWithValue(_FakeStore(results)),
      ],
      child: const MaterialApp(home: CareerScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a message when no tournament has finished yet',
      (tester) async {
    await _pump(tester, []);
    expect(find.textContaining('No tournaments finished'), findsOneWidget);
  });

  testWidgets('lists the player and every personality who has played',
      (tester) async {
    await _pump(tester, [
      _event([
        ('human', 'You', 2, 300, true),
        ('P1', 'Al Pro', 1, 900, false),
      ]),
    ]);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Al Pro'), findsOneWidget);
  });

  testWidgets('the player is listed first regardless of ROI', (tester) async {
    await _pump(tester, [
      _event([
        ('human', 'You', 5, 0, true), // a losing event for the player
        ('P1', 'Al Pro', 1, 900, false), // the best ROI in the field
      ]),
    ]);
    final you = tester.getCenter(find.text('You'));
    final al = tester.getCenter(find.text('Al Pro'));
    expect(you.dy, lessThan(al.dy));
  });
}
