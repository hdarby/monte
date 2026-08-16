import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/data/tournament_save_store.dart';
import 'package:monte/features/tournament/domain/tournament_save.dart';
import 'package:monte/features/tournament/presentation/widgets/saved_tournaments_dialog.dart';

TournamentSave _save(String name, DateTime at, {int level = 0}) => TournamentSave(
      name: name,
      savedAt: at,
      structureName: 'standard',
      startingStack: 10000,
      buyIn: 100,
      tableSize: 9,
      seed: 1,
      humanId: 'e0',
      humanName: 'You',
      levelIndex: level,
      handsThisLevel: 3,
      clockElapsedMs: 0,
      prizePool: 1800,
      finishOrder: const [],
      status: 'running',
      players: const [
        SavedPlayer(
          id: 'e0',
          name: 'You',
          isHuman: true,
          chips: 12000,
          tableId: 0,
          seatIndex: 0,
          status: 'active',
          rebuysUsed: 0,
        ),
        SavedPlayer(
          id: 'e1',
          name: 'Bot',
          isHuman: false,
          chips: 8000,
          tableId: 0,
          seatIndex: 1,
          status: 'busted',
          rebuysUsed: 0,
        ),
      ],
      tables: const [
        SavedTable(id: 0, playerIds: ['e0', 'e1']),
      ],
      profileIds: const {'e1': 'P001'},
      payoutFractions: const [1.0],
    );

/// Opens the dialog and returns whatever it popped with.
Future<TournamentSave?> _open(
  WidgetTester tester,
  TournamentSaveStore store,
) async {
  TournamentSave? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await SavedTournamentsDialog.show(context, store),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('the saved-tournaments browser', () {
    testWidgets('says so when there is nothing saved', (tester) async {
      await _open(tester, MemoryTournamentSaveStore());
      expect(find.textContaining('No saved tournaments yet'), findsOneWidget);
      // Nothing to act on, so nothing destructive is offered.
      expect(find.text('Delete all'), findsNothing);
    });

    testWidgets('lists saves newest first, with a datestamp', (tester) async {
      final store = MemoryTournamentSaveStore();
      await store.save(_save('Older', DateTime(2026, 1, 2, 9, 5)));
      await store.save(_save('Newer', DateTime(2026, 8, 15, 14, 32)));
      await _open(tester, store);

      expect(find.text('Newer'), findsOneWidget);
      expect(find.text('Older'), findsOneWidget);
      expect(find.textContaining('2026-08-15 14:32'), findsOneWidget);

      final newer = tester.getTopLeft(find.text('Newer')).dy;
      final older = tester.getTopLeft(find.text('Older')).dy;
      expect(newer, lessThan(older), reason: 'newest first');
    });

    testWidgets('load and delete stay disabled until something is picked',
        (tester) async {
      final store = MemoryTournamentSaveStore();
      await store.save(_save('One', DateTime(2026, 8, 15)));
      await _open(tester, store);

      FilledButton loadButton() =>
          tester.widget<FilledButton>(find.ancestor(
            of: find.text('Load'),
            matching: find.byType(FilledButton),
          ));
      expect(loadButton().onPressed, isNull);

      await tester.tap(find.text('One'));
      await tester.pumpAndSettle();
      expect(loadButton().onPressed, isNotNull);
    });

    testWidgets('loading returns the chosen save', (tester) async {
      final store = MemoryTournamentSaveStore();
      await store.save(_save('Pick me', DateTime(2026, 8, 15)));

      TournamentSave? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await SavedTournamentsDialog.show(context, store),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pick me'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.name, 'Pick me');
    });

    testWidgets('deleting one asks first, then removes it', (tester) async {
      final store = MemoryTournamentSaveStore();
      await store.save(_save('Keep', DateTime(2026, 8, 15)));
      await store.save(_save('Bin', DateTime(2026, 8, 14)));
      await _open(tester, store);

      await tester.tap(find.text('Bin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // A confirmation, not an instant deletion.
      expect(find.text('Delete this save?'), findsOneWidget);
      expect((await store.list()).length, 2);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect((await store.list()).map((s) => s.name), ['Keep']);
      expect(find.text('Bin'), findsNothing);
      expect(find.text('Keep'), findsOneWidget);
    });

    testWidgets('cancelling a delete keeps the save', (tester) async {
      final store = MemoryTournamentSaveStore();
      await store.save(_save('Safe', DateTime(2026, 8, 15)));
      await _open(tester, store);

      await tester.tap(find.text('Safe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();

      expect((await store.list()).length, 1);
    });

    testWidgets('delete all asks first, then empties the list', (tester) async {
      final store = MemoryTournamentSaveStore();
      await store.save(_save('A', DateTime(2026, 8, 15)));
      await store.save(_save('B', DateTime(2026, 8, 14)));
      await _open(tester, store);

      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all saved tournaments?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete all'));
      await tester.pumpAndSettle();

      expect(await store.list(), isEmpty);
      expect(find.textContaining('No saved tournaments yet'), findsOneWidget);
    });

    testWidgets('shows what state each save is in', (tester) async {
      final store = MemoryTournamentSaveStore();
      await store.save(_save('Deep run', DateTime(2026, 8, 15), level: 6));
      await _open(tester, store);
      // Level is 1-based for a human, and one of the two players has busted.
      expect(find.textContaining('level 7'), findsOneWidget);
      expect(find.textContaining('1 of 2 left'), findsOneWidget);
    });
  });

  group('naming a save', () {
    testWidgets('offers a sensible default and returns what was typed',
        (tester) async {
      String? name;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => name = await promptForSaveName(
                  context,
                  initial: 'WSOP Main · level 3',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('WSOP Main · level 3'), findsOneWidget);
      // The limitation is stated where the decision is made.
      expect(find.textContaining('hand in progress is not'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Friday');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(name, 'Friday');
    });

    testWidgets('cancelling returns nothing', (tester) async {
      String? name = 'unset';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    name = await promptForSaveName(context, initial: 'x'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(name, isNull);
    });
  });
}
