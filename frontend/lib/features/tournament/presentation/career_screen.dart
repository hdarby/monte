import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:monte/features/eval_history/presentation/eval_history_provider.dart';
import 'package:monte/features/tournament/domain/tournament_result.dart';

/// Career winnings across every finished tournament — for the player and
/// every named personality who's ever played one.
///
/// Previously the only way to see this at all was to finish a tournament and
/// tap through the session review to its last page; there was no way to check
/// in cold. This is a standing destination for exactly that, built from the
/// same [CareerRow] aggregation the session review uses, so the numbers always
/// agree.
class CareerScreen extends ConsumerWidget {
  const CareerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Career')),
      body: FutureBuilder<List<TournamentResult>>(
        future: ref.read(tournamentResultStoreProvider).loadAll(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final career = CareerRow.from(snapshot.data!);
          if (career.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No tournaments finished yet — play one out to the end and '
                  'it will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
              ),
            );
          }
          return _CareerTable(career: career);
        },
      ),
    );
  }
}

class _CareerTable extends StatelessWidget {
  const _CareerTable({required this.career});
  final List<CareerRow> career;

  @override
  Widget build(BuildContext context) {
    // The player first, then the field by ROI — you are reading this to find
    // out how you are doing, not to scroll for your own row. Mirrors the
    // ordering `SessionMarkdown`'s career table already uses.
    final you = career.where((c) => c.profileId == 'human');
    final rest = career.where((c) => c.profileId != 'human');
    final rows = [...you, ...rest];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Player')),
            DataColumn(label: Text('Events'), numeric: true),
            DataColumn(label: Text('Cashes'), numeric: true),
            DataColumn(label: Text('Cash %'), numeric: true),
            DataColumn(label: Text('In'), numeric: true),
            DataColumn(label: Text('Out'), numeric: true),
            DataColumn(label: Text('Net'), numeric: true),
            DataColumn(label: Text('ROI'), numeric: true),
            DataColumn(label: Text('Best'), numeric: true),
            DataColumn(label: Text('Faced you'), numeric: true),
          ],
          rows: [for (final c in rows) _rowFor(c)],
        ),
      ),
    );
  }

  DataRow _rowFor(CareerRow c) {
    final isYou = c.profileId == 'human';
    final netColor = c.net > 0
        ? Colors.greenAccent
        : c.net < 0
            ? Colors.redAccent
            : null;
    return DataRow(
      color: isYou
          ? WidgetStateProperty.all(Colors.amber.withValues(alpha: 0.08))
          : null,
      cells: [
        DataCell(Text(
          isYou ? 'You' : c.name,
          style: isYou ? const TextStyle(fontWeight: FontWeight.bold) : null,
        )),
        DataCell(Text('${c.played}')),
        DataCell(Text('${c.cashes}')),
        DataCell(Text('${c.cashRate.toStringAsFixed(0)}%')),
        DataCell(Text('\$${c.buyIns}')),
        DataCell(Text('\$${c.won}')),
        DataCell(Text(
          '${c.net >= 0 ? '+' : '-'}\$${c.net.abs()}',
          style: TextStyle(color: netColor, fontWeight: FontWeight.w600),
        )),
        DataCell(Text(
          '${c.roi >= 0 ? '+' : ''}${c.roi.toStringAsFixed(0)}%',
          style: TextStyle(color: netColor),
        )),
        DataCell(Text(c.bestPlace >= 1 << 29 ? '—' : '${c.bestPlace}')),
        DataCell(Text('${c.facedYou}')),
      ],
    );
  }
}
