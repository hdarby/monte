// A watchable, headless MULTI-TABLE tournament: 18 players across 3 six-max
// tables, real engine + bots + the M1 domain + the M3 controller. Prints the
// tournament arc — level-ups, tables breaking, the money bubble bursting, the
// final table, and the payouts — then asserts a clean finish.
//
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:monte/features/tournament/data/tournament_controller.dart';
import 'package:monte/features/tournament/domain/tournament_state.dart';
import 'package:monte/features/tournament/domain/tournament_structure.dart';

void main() {
  test('18-runner MTT plays down to a champion', () {
    const names = [
      'You', 'Ivan', 'Mai', 'Rex', 'Lena', 'Oto', 'Priya', 'Dana', 'Kojo',
      'Sven', 'Nia', 'Bo', 'Ada', 'Ren', 'Fay', 'Gus', 'Hana', 'Ivo',
    ];
    final c = TournamentController.create(
      structure: TournamentStructure.turbo(
          clockMode: LevelClockMode.hands, startingStack: 1500),
      entrants: 18,
      buyIn: 100,
      tableSize: 6,
      seed: 11,
      humanSeat: true,
      names: names,
    );
    final s = c.state;

    print('=== 18-runner Turbo MTT — 3 tables of 6, \$100 buy-in ===');
    print('pool \$${s.prizePool}, top ${s.paidPlaces} paid: ${s.payoutTable}\n');

    var lastLevel = -1;
    var lastTables = -1;
    var lastFinished = 0;
    var announcedMoney = false;

    c.onRound = () {
      final tables = s.tables.where((t) => t.size > 0).length;
      if (s.currentLevel.level != lastLevel || tables != lastTables) {
        lastLevel = s.currentLevel.level;
        lastTables = tables;
        print('L${s.currentLevel.level} '
            '${s.currentLevel.smallBlind}/${s.currentLevel.bigBlind}'
            '${s.currentLevel.ante > 0 ? '+${s.currentLevel.ante}' : ''}  '
            '· $tables table(s) · ${s.playersRemaining} left '
            '· avg ${s.averageStack}');
      }
      // Announce eliminations as they happen.
      if (s.finishOrder.length != lastFinished) {
        for (var i = lastFinished; i < s.finishOrder.length; i++) {
          final p = s.players[s.finishOrder[i]]!;
          if (p.finishPlace == 1) continue; // champion printed below
          final money = p.prizeWon > 0 ? ' — \$${p.prizeWon} 💰' : '';
          print('   ✗ ${_ord(p.finishPlace!)}  ${p.name}$money');
        }
        lastFinished = s.finishOrder.length;
      }
      if (!announcedMoney && s.inMoney) {
        announcedMoney = true;
        print('   🫧 bubble burst — ${s.playersRemaining} in the money!');
      }
    };

    c.runToCompletion();

    final champ = s.players.values.firstWhere((p) => p.finishPlace == 1);
    print('\n🏆 Champion: ${champ.name} — \$${champ.prizeWon}  '
        '(${c.handsPlayed} hands)');
    print('\nIn the money:');
    for (final p in (s.players.values.where((p) => p.prizeWon > 0).toList()
      ..sort((a, b) => a.finishPlace!.compareTo(b.finishPlace!)))) {
      print('  ${_ord(p.finishPlace!)}  ${p.name}  \$${p.prizeWon}');
    }
    final you = s.players['e0']!;
    print('\nYou finished ${_ord(you.finishPlace!)} of 18'
        '${you.prizeWon > 0 ? ' for \$${you.prizeWon}' : ''}.');

    expect(s.status, TournamentStatus.finished);
    expect(s.players.values.where((p) => p.finishPlace == 1).length, 1);
    expect(s.players.values.fold(0, (a, p) => a + p.prizeWon), s.prizePool);
  });
}

String _ord(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}
