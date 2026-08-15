// ignore_for_file: avoid_print
//
// Interactive player-creation script.
//
//   dart run tool/create_player.dart            # create + write
//   dart run tool/create_player.dart --dry-run  # prompt, print JSON, no write
//
// Asks whether the new player is a pro or recreational, gathers their style and
// the scored general traits (and, for pros, which special characteristics from
// the catalog apply and how well), builds a PlayerProfile via PlayerFactory, and
// regenerates lib/core/domain/ai/custom_players.dart. Pure Dart; not shipped.
import 'dart:convert';
import 'dart:io';

import 'package:monte/core/domain/ai/characteristic_catalog.dart';
import 'package:monte/core/domain/ai/custom_players.dart';
import 'package:monte/core/domain/ai/home_game_profiles.dart';
import 'package:monte/core/domain/ai/player_factory.dart';
import 'package:monte/core/domain/ai/player_profile.dart';
import 'package:monte/core/domain/ai/player_profiles.dart';
import 'package:monte/core/domain/ai/player_source.dart';

const _outPath = 'lib/core/domain/ai/custom_players.dart';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  print('=== Monte player creator ===\n');

  final name = _ask('Player name');
  final isPro = _askChoice('Type', ['Recreational', 'Pro']) == 1;

  final existingIds = {
    for (final p in builtInProfiles) p.id,
    for (final p in homeGameProfiles) p.id,
  };

  final profile = isPro
      ? _createPro(name, PlayerFactory.nextId('P', existingIds))
      : _createRec(name, PlayerFactory.nextId('H', existingIds));

  print('\n--- ${profile.name} (${profile.id}) ---');
  print(const JsonEncoder.withIndent('  ').convert(profile.toJson()));
  final warnings = profile.validate();
  if (warnings.isNotEmpty) {
    print('\n⚠  ${warnings.join('\n⚠  ')}');
  }

  if (dryRun) {
    print('\n[--dry-run] not written.');
    return;
  }
  if (!_askYesNo('\nWrite this player into $_outPath?')) {
    print('Aborted; nothing written.');
    return;
  }

  final recs = [...customRecreationalPlayers, if (!isPro) profile];
  final pros = [...customPros, if (isPro) profile];
  File(_outPath).writeAsStringSync(
    customPlayersDartFile(recs: recs, pros: pros),
  );
  print('Wrote $_outPath. Run `flutter analyze` to confirm it compiles.');
}

// ---- Flows ------------------------------------------------------------------

PlayerProfile _createRec(String name, String id) {
  print('\nRecreational player — describe how $name plays.\n');
  final strength = _askInt('Overall strength (1 = beginner … 10 = near-pro)',
      min: 1, max: 10);
  // Looseness → vpip/pfr gap (looser & more passive = wider gap).
  final loose = _askChoice('How loose are they preflop?',
      ['Nit (very tight)', 'Tight', 'Balanced', 'Loose', 'Maniac (any two)']);
  final passive = _askChoice('When they play, do they raise or just call?',
      ['Mostly calls/limps', 'Mixed', 'Mostly raises']);
  final bluff = _askChoice('How often do they bluff?',
      ['Never', 'Rarely', 'Sometimes', 'Often', 'Constantly']);
  final sizing = _askChoice('Typical bet sizing',
      ['Small / min-bets', 'Normal', 'Big / overbets']);
  final tilt = _score('Tilt control (0 = spews after a loss, 100 = ice)');

  const vpips = [0.16, 0.22, 0.28, 0.40, 0.60];
  final vpip = vpips[loose];
  // Passive players raise a smaller share of the hands they play.
  final pfrFrac = [0.45, 0.65, 0.85][passive];
  final pfr = (vpip * pfrFrac).clamp(0.02, vpip);
  final threeBet = (pfr * 0.3).clamp(0.01, pfr);
  final exploit = [0.08, 0.20, 0.40, 0.60, 0.85][bluff];
  final risk = [0.85, 1.0, 1.2][sizing];

  final gt = _generalTraits();
  final opp = _score('Reading opponents / tendencies '
      '(0 = oblivious, 100 = sharp)');
  final desc = _ask('One-line strengths/weaknesses (optional)', optional: true);

  return PlayerFactory.recreational(
    id: id,
    name: name,
    strength: strength,
    vpip: vpip,
    pfr: pfr.toDouble(),
    threeBet: threeBet.toDouble(),
    exploitativeWeight: exploit,
    riskPremium: risk,
    tiltResistance: tilt,
    opponentReading: opp,
    generalTraits: gt,
    description: desc.isEmpty ? null : desc,
  );
}

PlayerProfile _createPro(String name, String id) {
  print('\nPro — describe how $name plays.\n');
  final desc = _ask('Description of how they play');
  final archetype = _ask('Short archetype label (e.g. GTO_Wizard)',
      optional: true);
  print('\nPreflop style:');
  print('(the calibrator needs a real open range and a VPIP>PFR gap — e.g. '
      '24/19/8, 30/24/10)');
  late double vpip, pfr, threeBet;
  while (true) {
    vpip = _score('VPIP % (how often they enter a pot)');
    pfr = _score('PFR % (how often they raise preflop)');
    threeBet = _score('3-bet %');
    final bad = PlayerProfile.preflopFeasibility(
        vpip: vpip, pfr: pfr, threeBet: threeBet);
    if (bad.isEmpty) break;
    print('\n⚠  These targets can’t be realised by the calibrator:');
    for (final m in bad) {
      print('   • $m');
    }
    print('   Re-enter VPIP / PFR / 3-bet.\n');
  }
  final tilt = _score('Tilt control (0–100)');
  final opp = _score('Reading opponents / tendencies (0–100)');

  // The recreational flow has always asked these; the pro flow did not, so every
  // custom pro was written out with the same defaults (0.30 / 1.0) no matter how
  // they were described — an "aggressive bully" came out identical to a "GTO
  // standard". Ask, the same way.
  final deviate = _askChoice('How much do they deviate to attack an opponent?',
      ['Barely — plays their own game', 'Some', 'A lot', 'Constantly hunting']);
  final sizing = _askChoice('Typical bet sizing',
      ['Small / controlled', 'Normal', 'Big / overbets']);
  final exploitWeight = [0.10, 0.30, 0.55, 0.80][deviate];
  final risk = [0.85, 1.0, 1.25][sizing];

  print('\nSpecial characteristics — which apply to $name?');
  print('(answer the % they use each; leave blank / 0 to skip)\n');
  final chosen = <PlayerCharacteristic>[];
  for (final c in characteristicCatalog) {
    print('• ${c.name} — ${c.description}');
    final pct = _score('   Proficiency for "${c.name}" (0 = skip)');
    if (pct > 0) chosen.add(PlayerCharacteristic(id: c.id, proficiency: pct));
  }

  final gt = _generalTraits();

  return PlayerFactory.pro(
    id: id,
    name: name,
    vpip: vpip,
    pfr: pfr,
    threeBet: threeBet,
    exploitativeWeight: exploitWeight,
    riskPremium: risk,
    tiltResistance: tilt,
    opponentReading: opp,
    characteristics: chosen,
    generalTraits: gt,
    description: desc,
    archetype: archetype.isEmpty ? 'Custom_Pro' : archetype,
  );
}

/// The three genuinely-new scored dimensions (tilt + opponent reading are asked
/// separately because they map onto existing behavioral fields).
GeneralTraits _generalTraits() {
  print('\nGeneral traits (0–100):');
  return GeneralTraits(
    positionAwareness: _score('Position awareness'),
    potOdds: _score('Understanding of pot odds'),
    impliedOdds: _score('Understanding of implied odds'),
  );
}

// ---- Prompt helpers ---------------------------------------------------------

String _ask(String prompt, {bool optional = false}) {
  while (true) {
    stdout.write('$prompt${optional ? ' (optional)' : ''}: ');
    final line = stdin.readLineSync()?.trim() ?? '';
    if (line.isNotEmpty || optional) return line;
    print('  Please enter a value.');
  }
}

int _askInt(String prompt, {required int min, required int max}) {
  while (true) {
    final n = int.tryParse(_ask(prompt));
    if (n != null && n >= min && n <= max) return n;
    print('  Enter a whole number $min–$max.');
  }
}

/// A 0–100 score returned as a 0–1 fraction. Blank = 0.
///
/// Values strictly between 0 and 1 are rejected rather than accepted. The prompt
/// asks for a percentage, but `num.tryParse` happily took `0.85` and returned
/// 0.0085 — that silent hundred-fold error is how Jeremy Ausmus ended up with a
/// GTO adherence of 0.0085 instead of 0.85. Nobody means "0.85%", so treating it
/// as a typo and asking again is always right.
double _score(String prompt) {
  while (true) {
    stdout.write('$prompt: ');
    final line = stdin.readLineSync()?.trim() ?? '';
    if (line.isEmpty) return 0.0;
    final n = num.tryParse(line);
    if (n != null && n > 0 && n < 1) {
      print('  That looks like a fraction — enter ${(n * 100).round()} for '
          '${(n * 100).round()}%, not $n.');
      continue;
    }
    if (n != null && n >= 0 && n <= 100) return (n / 100).toDouble();
    print('  Enter a number 0–100 (or blank for 0).');
  }
}

/// Presents [options] and returns the chosen index.
int _askChoice(String prompt, List<String> options) {
  while (true) {
    print(prompt);
    for (var i = 0; i < options.length; i++) {
      print('  ${i + 1}) ${options[i]}');
    }
    stdout.write('Choose 1–${options.length}: ');
    final n = int.tryParse(stdin.readLineSync()?.trim() ?? '');
    if (n != null && n >= 1 && n <= options.length) return n - 1;
    print('  Enter a number 1–${options.length}.');
  }
}

bool _askYesNo(String prompt) {
  stdout.write('$prompt [y/N]: ');
  final line = (stdin.readLineSync() ?? '').trim().toLowerCase();
  return line == 'y' || line == 'yes';
}
