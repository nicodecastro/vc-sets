import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appControllerProvider);
    final games = data.tournaments
        .expand((tournament) => tournament.games)
        .toList();
    final active = data.tournaments
        .where((item) => item.status != TournamentStatus.completed)
        .length;
    final awaiting = games
        .where((item) => item.status == GameStatus.awaitingReconciliation)
        .length;
    final backupOld =
        data.lastBackupAt == null ||
        DateTime.now().difference(data.lastBackupAt!).inDays >= 7;
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const PageHeader(
          title: 'Match day, under control',
          subtitle:
              'Everything stays on this device until you choose to export it.',
        ),
        if (backupOld)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('A fresh backup is recommended'),
                subtitle: const Text(
                  'Browser storage can be cleared by the operating system. Export after every match day.',
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => context.go('/backup'),
                  child: const Text('Back up'),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width >= 900 ? 3 : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: MediaQuery.sizeOf(context).width >= 900
                ? 2.1
                : 3.2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MetricCard(
                label: 'Active tournaments',
                value: '$active',
                icon: Icons.emoji_events_outlined,
              ),
              _MetricCard(
                label: 'Games recorded',
                value: '${games.length}',
                icon: Icons.sports_volleyball,
              ),
              _MetricCard(
                label: 'Need reconciliation',
                value: '$awaiting',
                icon: Icons.compare_arrows,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                'Recent tournaments',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.go('/tournaments'),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('View all'),
              ),
            ],
          ),
        ),
        if (data.tournaments.isEmpty)
          EmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'Create your first tournament',
            message: 'Add tournament rosters, generate fixtures, and begin scoring offline.',
            action: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/tournaments'),
                  icon: const Icon(Icons.add),
                  label: const Text('New tournament'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final id = await ref
                          .read(appControllerProvider.notifier)
                          .loadSampleTournament();
                      if (context.mounted) context.go('/tournaments/$id');
                    } catch (error) {
                      if (context.mounted) showError(context, error);
                    }
                  },
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Load sample tournament'),
                ),
              ],
            ),
          )
        else
          ...data.tournaments.reversed
              .take(4)
              .map(
                (tournament) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      title: Text(
                        tournament.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${tournament.teams.length} teams • ${tournament.games.length} games • ${tournament.venue}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/tournaments/${tournament.id}'),
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          CircleAvatar(radius: 25, child: Icon(icon)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
