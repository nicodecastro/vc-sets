import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../domain/sample_tournament.dart';
import '../widgets/common.dart';

class TournamentsPage extends ConsumerWidget {
  const TournamentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(appControllerProvider).tournaments;
    return Column(
      children: [
        PageHeader(
          title: 'Tournaments',
          subtitle: 'Tournament rosters are snapshots, so later events never rewrite history.',
          actions: [
            OutlinedButton.icon(
              onPressed: () =>
                  tournaments.any((item) => item.id == sampleTournamentId)
                  ? _refreshSample(context, ref)
                  : _loadSample(context, ref),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                tournaments.any((item) => item.id == sampleTournamentId)
                    ? 'Refresh sample tournament'
                    : 'Load sample tournament',
              ),
            ),
            FilledButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New tournament'),
            ),
          ],
        ),
        Expanded(
          child: tournaments.isEmpty
              ? EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: 'No tournaments yet',
                  message: 'Create one, add its teams and rosters, then generate the schedule.',
                  action: FilledButton(
                    onPressed: () => _create(context, ref),
                    child: const Text('Create tournament'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  itemCount: tournaments.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final tournament = tournaments[index];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(18),
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(
                          tournament.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${DateFormat.yMMMd().format(tournament.startsOn)} • ${tournament.venue}\n${tournament.teams.length} teams • ${tournament.games.length} games',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.go('/tournaments/${tournament.id}'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _loadSample(BuildContext context, WidgetRef ref) async {
    try {
      final id = await ref
          .read(appControllerProvider.notifier)
          .loadSampleTournament();
      if (context.mounted) context.go('/tournaments/$id');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _refreshSample(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refresh sample tournament?'),
        content: const Text(
          'This replaces any changes you made to the fictional sample tournament. Your other tournaments stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Refresh sample'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(appControllerProvider.notifier).refreshSampleTournament();
      if (context.mounted) context.go('/tournaments/$sampleTournamentId');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final venue = TextEditingController();
    var start = DateTime.now();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New tournament'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tournament name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: venue,
                  decoration: const InputDecoration(labelText: 'Venue'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Starts on'),
                  subtitle: Text(DateFormat.yMMMMd().format(start)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                      initialDate: start,
                    );
                    if (picked != null) setState(() => start = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || name.text.trim().isEmpty) return;
    try {
      final id = await ref
          .read(appControllerProvider.notifier)
          .createTournament(
            name: name.text,
            venue: venue.text,
            startsOn: start,
            endsOn: start,
          );
      if (context.mounted) context.go('/tournaments/$id');
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}
