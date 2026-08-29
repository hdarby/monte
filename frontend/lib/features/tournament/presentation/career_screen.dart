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

class _CareerTable extends StatefulWidget {
  const _CareerTable({required this.career});
  final List<CareerRow> career;

  @override
  State<_CareerTable> createState() => _CareerTableState();
}

class _CareerTableState extends State<_CareerTable> {
  /// Null until the player taps a header — the default ordering (you first,
  /// then the field by ROI) mirrors `SessionMarkdown`'s career table and
  /// stays until the player asks for something else.
  int? _sortColumn;
  bool _sortAscending = false;

  /// One comparable key-getter per column, in the same order as [_columns].
  /// `Comparable` (not a raw type) so string and numeric columns share the
  /// same sort call.
  static final List<Comparable<dynamic> Function(CareerRow)> _sortKeys = [
    (c) => c.profileId == 'human' ? '' : c.name, // "You" always sorts first
    (c) => c.played,
    (c) => c.cashes,
    (c) => c.cashRate,
    (c) => c.buyIns,
    (c) => c.won,
    (c) => c.net,
    (c) => c.roi,
    (c) => c.bestPlace,
    (c) => c.facedYou,
  ];

  static const _columns = [
    'Player',
    'Events',
    'Cashes',
    'Cash %',
    'In',
    'Out',
    'Net',
    'ROI',
    'Best',
    'Faced you',
  ];

  void _sort(int column) => setState(() {
        if (_sortColumn == column) {
          _sortAscending = !_sortAscending;
        } else {
          _sortColumn = column;
          // Money/rate columns read naturally biggest-first; "Best" (a finish
          // place) and the player name read naturally smallest/A-first.
          _sortAscending = column == 0 || column == 8;
        }
      });

  @override
  Widget build(BuildContext context) {
    final sortColumn = _sortColumn;
    List<CareerRow> rows;
    if (sortColumn == null) {
      // The player first, then the field by ROI — you are reading this to
      // find out how you are doing, not to scroll for your own row.
      final you = widget.career.where((c) => c.profileId == 'human');
      final rest = widget.career.where((c) => c.profileId != 'human');
      rows = [...you, ...rest];
    } else {
      final key = _sortKeys[sortColumn];
      rows = [...widget.career]
        ..sort((a, b) => _sortAscending
            ? key(a).compareTo(key(b))
            : key(b).compareTo(key(a)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: _sortColumn,
          sortAscending: _sortAscending,
          columns: [
            for (var i = 0; i < _columns.length; i++)
              DataColumn(
                label: Text(_columns[i]),
                numeric: i > 0,
                onSort: (column, _) => _sort(column),
              ),
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
