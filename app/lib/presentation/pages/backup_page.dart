import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/file_exchange.dart';
import '../../application/providers.dart';
import '../../domain/game_linking.dart';
import '../../domain/models.dart';
import '../../domain/packages.dart';
import '../widgets/common.dart';

class BackupPage extends ConsumerWidget {
  const BackupPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appControllerProvider);
    return ListView(
      padding: const EdgeInsets.only(bottom: 30),
      children: [
        const PageHeader(
          title: 'Data & exchange',
          subtitle: 'Your data is local. Export it deliberately, and store copies somewhere safe.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Full backup',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data.lastBackupAt == null
                        ? 'No backup recorded on this device.'
                        : 'Last backup: ${DateFormat.yMMMd().add_jm().format(data.lastBackupAt!)}',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _backup(context, ref),
                        icon: const Icon(Icons.download),
                        label: const Text('Export full backup'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _restore(context, ref),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Preview & restore'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Backups are plain JSON and may contain player information. Keep exported files in an appropriately protected location.',
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import a game package',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use this to initialize the second scorer device or bring its completed scorer log back to the tournament device.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () => _importGame(context, ref),
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('Import .vcgame'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.offline_bolt_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Offline guarantee: scoring, reports, exports, and imports do not require an account or network connection. The hosted PWA contains only application code.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    try {
      await const FileExchangeService().exportBackup(
        ref.read(appControllerProvider),
      );
      await ref.read(appControllerProvider.notifier).markBackedUp();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Backup exported.')));
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      final backup = await const FileExchangeService().pickBackup();
      if (backup == null || !context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: Text(
            'The package contains ${backup.tournaments.length} tournament(s). It will replace the current local dataset after confirmation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Replace local data'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await ref.read(appControllerProvider.notifier).restoreBackup(backup);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup restored successfully.')),
          );
        }
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _importGame(BuildContext context, WidgetRef ref) async {
    try {
      final package = await const FileExchangeService().pickGamePackage();
      if (package == null || !context.mounted) return;
      final data = ref.read(appControllerProvider);
      final game = package.tournament.games.firstWhere(
        (item) => item.id == package.gameId,
      );
      final home = package.tournament.team(game.homeTeamId);
      final away = package.tournament.team(game.awayTeamId);
      final exactGameExists = data.tournaments.any(
        (tournament) =>
            tournament.id == package.tournament.id &&
            tournament.games.any((item) => item.id == package.gameId),
      );
      final packageAlreadyImported = data.importedPackageIds.contains(
        package.manifest.packageId,
      );
      final linkCandidates = <({Tournament tournament, Game game})>[
        for (final tournament in data.tournaments)
          for (final localGame in tournament.games)
            if (localGame.status != GameStatus.finalized &&
                localGame.logs.length < 2 &&
                !(tournament.id == package.tournament.id &&
                    localGame.id == package.gameId))
              (tournament: tournament, game: localGame),
      ];
      final canLink =
          package.log != null &&
          linkCandidates.isNotEmpty &&
          (!exactGameExists || packageAlreadyImported);
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import game package?'),
          content: Text(
            '${package.tournament.name}\n${home.name} vs ${away.name}\n${package.log == null ? 'Starter package' : 'Includes a scorer log with ${package.log!.rallies.length} rallies'}'
            '${canLink ? '\n\nIf this is the same real-world match as a separately created local game, choose Link to existing.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            if (canLink && !packageAlreadyImported)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'separate'),
                child: const Text('Import separately'),
              ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, canLink ? 'link' : 'import'),
              child: Text(canLink ? 'Link to existing' : 'Import'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (choice == 'link') {
        await _linkGamePackage(context, ref, package, linkCandidates);
      } else if (choice == 'import' || choice == 'separate') {
        await ref
            .read(appControllerProvider.notifier)
            .importGamePackage(package);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Game package imported.')),
          );
        }
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _linkGamePackage(
    BuildContext context,
    WidgetRef ref,
    GamePackage package,
    List<({Tournament tournament, Game game})> candidates,
  ) async {
    final sourceLog = package.log!;
    final sourceGame = package.tournament.games.firstWhere(
      (game) => game.id == package.gameId,
    );
    final sourceHome = package.tournament.team(sourceGame.homeTeamId);
    final sourceAway = package.tournament.team(sourceGame.awayTeamId);
    const linker = GameLinkingService();
    var candidateIndex = 0;
    var sourceHomeMapsToTargetHome = _suggestDirectMapping(
      sourceHome,
      sourceAway,
      candidates.first.tournament.team(candidates.first.game.homeTeamId),
      candidates.first.tournament.team(candidates.first.game.awayTeamId),
    );
    var links = <GameLinkPlayer>[];
    var playerMappings = <String, String?>{};

    void resetPlayerMappings() {
      final candidate = candidates[candidateIndex];
      links = linker.playerLinks(
        sourceTournament: package.tournament,
        sourceGame: sourceGame,
        sourceLog: sourceLog,
        targetTournament: candidate.tournament,
        targetGame: candidate.game,
        sourceHomeMapsToTargetHome: sourceHomeMapsToTargetHome,
      );
      playerMappings = linker.suggestPlayerMappings(links);
    }

    resetPlayerMappings();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final candidate = candidates[candidateIndex];
          final targetHome = candidate.tournament.team(
            candidate.game.homeTeamId,
          );
          final targetAway = candidate.tournament.team(
            candidate.game.awayTeamId,
          );
          final errors = linker.validatePlayerMappings(links, playerMappings);
          final sourceRules = package.tournament.rulesFor(sourceGame);
          final targetRules = candidate.tournament.rulesFor(candidate.game);
          final rulesDiffer = !_sameMatchRules(sourceRules, targetRules);
          return AlertDialog(
            title: const Text('Link scorer log to existing game'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Choose the local version of this match. Team and player UUIDs will be rewritten only after you confirm the mapping.',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: candidateIndex,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Local game',
                      ),
                      items: [
                        for (var index = 0; index < candidates.length; index++)
                          DropdownMenuItem(
                            value: index,
                            child: Text(_candidateLabel(candidates[index])),
                          ),
                      ],
                      onChanged: (value) {
                        candidateIndex = value!;
                        final next = candidates[candidateIndex];
                        sourceHomeMapsToTargetHome = _suggestDirectMapping(
                          sourceHome,
                          sourceAway,
                          next.tournament.team(next.game.homeTeamId),
                          next.tournament.team(next.game.awayTeamId),
                        );
                        resetPlayerMappings();
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<bool>(
                      key: ValueKey(
                        'orientation-$candidateIndex-$sourceHomeMapsToTargetHome',
                      ),
                      initialValue: sourceHomeMapsToTargetHome,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Team mapping',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: true,
                          child: Text(
                            '${sourceHome.shortCode} → ${targetHome.shortCode}, ${sourceAway.shortCode} → ${targetAway.shortCode}',
                          ),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text(
                            '${sourceHome.shortCode} → ${targetAway.shortCode}, ${sourceAway.shortCode} → ${targetHome.shortCode}',
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        sourceHomeMapsToTargetHome = value!;
                        resetPlayerMappings();
                        setDialogState(() {});
                      },
                    ),
                    if (rulesDiffer) ...[
                      const SizedBox(height: 12),
                      Text(
                        'The match rules differ. The local game rules will control completion and finalization.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const Divider(height: 28),
                    Text(
                      'Player mapping',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Players are matched by jersey number first. Review every row before linking.',
                    ),
                    const SizedBox(height: 12),
                    for (final link in links) ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'player-$candidateIndex-$sourceHomeMapsToTargetHome-${link.sourcePlayer.id}',
                        ),
                        initialValue: playerMappings[link.sourcePlayer.id],
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText:
                              '${link.sourceTeam.shortCode} #${link.sourcePlayer.number} ${link.sourcePlayer.name} → ${link.targetTeam.shortCode}',
                        ),
                        items: link.targetTeam.players
                            .map(
                              (player) => DropdownMenuItem(
                                value: player.id,
                                child: Text(
                                  '#${player.number} ${player.name} (${player.position.name})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setDialogState(
                          () => playerMappings[link.sourcePlayer.id] = value,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (errors.isNotEmpty)
                      Text(
                        errors.join('\n'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: errors.isEmpty
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: const Text('Link scorer log'),
              ),
            ],
          );
        },
      ),
    );
    if (accepted != true || !context.mounted) return;
    final target = candidates[candidateIndex];
    await ref
        .read(appControllerProvider.notifier)
        .linkGamePackage(
          package,
          targetTournamentId: target.tournament.id,
          targetGameId: target.game.id,
          sourceHomeMapsToTargetHome: sourceHomeMapsToTargetHome,
          playerIdMap: playerMappings,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scorer log linked. The game is ready to reconcile.'),
        ),
      );
    }
  }

  static String _candidateLabel(
    ({Tournament tournament, Game game}) candidate,
  ) {
    final home = candidate.tournament.team(candidate.game.homeTeamId);
    final away = candidate.tournament.team(candidate.game.awayTeamId);
    return '${candidate.tournament.name} • ${home.shortCode} vs ${away.shortCode} • ${DateFormat.MMMd().format(candidate.game.scheduledAt)}';
  }

  static bool _suggestDirectMapping(
    TournamentTeam sourceHome,
    TournamentTeam sourceAway,
    TournamentTeam targetHome,
    TournamentTeam targetAway,
  ) {
    final direct =
        _teamSimilarity(sourceHome, targetHome) +
        _teamSimilarity(sourceAway, targetAway);
    final reversed =
        _teamSimilarity(sourceHome, targetAway) +
        _teamSimilarity(sourceAway, targetHome);
    return direct >= reversed;
  }

  static int _teamSimilarity(TournamentTeam source, TournamentTeam target) {
    final sourceName = source.name.trim().toLowerCase();
    final targetName = target.name.trim().toLowerCase();
    final sourceCode = source.shortCode.trim().toLowerCase();
    final targetCode = target.shortCode.trim().toLowerCase();
    return (sourceName == targetName ? 2 : 0) +
        (sourceCode == targetCode ? 1 : 0);
  }

  static bool _sameMatchRules(MatchRules source, MatchRules target) =>
      source.setsToWin == target.setsToWin &&
      source.maxSets == target.maxSets &&
      source.regularSetTarget == target.regularSetTarget &&
      source.decidingSetTarget == target.decidingSetTarget &&
      source.setTargets.length == target.setTargets.length &&
      source.setTargets.entries.every(
        (entry) => target.setTargets[entry.key] == entry.value,
      ) &&
      source.winBy == target.winBy;
}
