import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/file_exchange.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../../domain/statistics.dart';
import '../widgets/common.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});
  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String? selectedId;
  @override
  Widget build(BuildContext context) {
    final tournaments = ref.watch(appControllerProvider).tournaments;
    if (tournaments.isEmpty) {
      return const Column(
        children: [
          PageHeader(
            title: 'Reports',
            subtitle: 'Finalized games feed tournament and player totals.',
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.bar_chart,
              title: 'Nothing to report yet',
              message: 'Create a tournament and finalize a match first.',
            ),
          ),
        ],
      );
    }
    selectedId ??= tournaments.first.id;
    final tournament = tournaments.firstWhere(
      (item) => item.id == selectedId,
      orElse: () => tournaments.first,
    );
    final standings = const StatisticsService().standings(tournament);
    final standingsByPool =
        tournament.format == TournamentFormat.poolsThenKnockout
        ? {
            for (var pool = 1; pool <= tournament.poolCount; pool++)
              pool: const StatisticsService().standings(
                tournament,
                poolNumber: pool,
              ),
          }
        : {1: standings};
    final playerStats = const StatisticsService().playerStatsSummary(
      tournament,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        PageHeader(
          title: 'Reports',
          subtitle: 'Only finalized, reconciled games are included.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => _export(
                () =>
                    const FileExchangeService().exportStandingsCsv(tournament),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Standings CSV'),
            ),
            OutlinedButton.icon(
              onPressed: () => _export(
                () => const FileExchangeService().exportPlayersCsv(tournament),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Player stats CSV'),
            ),
            OutlinedButton.icon(
              onPressed: () => _export(
                () =>
                    const FileExchangeService().exportPrintableHtml(tournament),
              ),
              icon: const Icon(Icons.print),
              label: const Text('Printable report'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: DropdownButtonFormField<String>(
            initialValue: tournament.id,
            decoration: const InputDecoration(labelText: 'Tournament'),
            items: tournaments
                .map(
                  (item) =>
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                )
                .toList(),
            onChanged: (value) => setState(() => selectedId = value),
          ),
        ),
        const SizedBox(height: 22),
        _ReportSection(
          title: tournament.format == TournamentFormat.poolsThenKnockout
              ? 'Pool standings'
              : 'Standings',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in standingsByPool.entries) ...[
                if (standingsByPool.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'Pool ${String.fromCharCode('A'.codeUnitAt(0) + entry.key - 1)}',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                _standingsTable(entry.value),
              ],
            ],
          ),
        ),
        _ReportSection(
          title: 'Player stats summary',
          child: playerStats.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Add tournament roster players to build the summary.',
                  ),
                )
              : _playerStatsTable(playerStats),
        ),
      ],
    );
  }

  Widget _standingsTable(List<StandingRow> standings) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: const [
        DataColumn(label: Text('#')),
        DataColumn(label: Text('Team')),
        DataColumn(label: Text('P')),
        DataColumn(label: Text('W')),
        DataColumn(label: Text('L')),
        DataColumn(label: Text('Pts')),
        DataColumn(label: Text('Sets')),
        DataColumn(label: Text('Points')),
      ],
      rows: [
        for (var i = 0; i < standings.length; i++)
          DataRow(
            cells: [
              DataCell(Text('${i + 1}')),
              DataCell(Text(standings[i].team.name)),
              DataCell(Text('${standings[i].played}')),
              DataCell(Text('${standings[i].wins}')),
              DataCell(Text('${standings[i].losses}')),
              DataCell(Text('${standings[i].matchPoints}')),
              DataCell(
                Text('${standings[i].setsWon}-${standings[i].setsLost}'),
              ),
              DataCell(
                Text('${standings[i].pointsWon}-${standings[i].pointsLost}'),
              ),
            ],
          ),
      ],
    ),
  );

  Widget _playerStatsTable(List<PlayerStatRow> rows) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      headingRowColor: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      columns: [
        const DataColumn(label: Text('Team')),
        const DataColumn(label: Text('Last name')),
        const DataColumn(label: Text('#'), numeric: true),
        for (final column in playerStatColumns)
          DataColumn(label: Text(column), numeric: true),
        const DataColumn(label: Text('Games played'), numeric: true),
        const DataColumn(label: Text('Sets played'), numeric: true),
        const DataColumn(label: Text('Games won'), numeric: true),
      ],
      rows: [
        for (final row in rows)
          DataRow(
            cells: [
              DataCell(Text(row.team.name)),
              DataCell(Text(row.lastName)),
              DataCell(Text('${row.player.number}')),
              for (final column in playerStatColumns)
                DataCell(Text('${row.counts[column] ?? 0}')),
              DataCell(Text('${row.gamesPlayed}')),
              DataCell(Text('${row.setsPlayed}')),
              DataCell(Text('${row.gamesWon}')),
            ],
          ),
      ],
    ),
  );

  Future<void> _export(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('CSV exported.')));
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    ),
  );
}
