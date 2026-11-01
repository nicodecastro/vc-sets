import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../application/file_exchange.dart';
import '../../application/providers.dart';
import '../../domain/models.dart';
import '../../domain/scoring.dart';
import '../widgets/common.dart';

class TournamentDetailPage extends ConsumerWidget {
  const TournamentDetailPage({super.key, required this.tournamentId});
  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appControllerProvider);
    final tournament = data.tournaments
        .where((item) => item.id == tournamentId)
        .firstOrNull;
    if (tournament == null) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Tournament not found',
        message: 'It may have been replaced by a restored backup.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        PageHeader(
          title: tournament.name,
          subtitle:
              '${_dateRange(tournament)} • ${tournament.venue} • ${tournament.status.name} • ${_formatLabel(tournament.format)}',
          actions: [
            FilledButton.tonalIcon(
              onPressed: () => _editTournament(context, ref, tournament),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit tournament'),
            ),
            OutlinedButton.icon(
              onPressed: () => _editRules(context, ref, tournament),
              icon: const Icon(Icons.tune),
              label: const Text('Rules'),
            ),
            OutlinedButton.icon(
              onPressed: () => _addTeam(context, ref),
              icon: const Icon(Icons.group_add),
              label: const Text('Add team'),
            ),
            OutlinedButton.icon(
              onPressed:
                  tournament.teams.length < 2 ||
                      tournament.format == TournamentFormat.knockoutOnly
                  ? null
                  : () => _addGame(context, ref, tournament),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Add game'),
            ),
            FilledButton.icon(
              onPressed:
                  tournament.teams.length < 2 ||
                      tournament.format == TournamentFormat.knockoutOnly
                  ? null
                  : () => _generate(context, ref),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Round robin'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: () => _deleteTournament(context, ref, tournament),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete tournament'),
            ),
          ],
        ),
        _Section(
          title: 'Teams rosters',
          child: tournament.teams.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Add at least two teams, then enter each tournament roster.',
                  ),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: tournament.teams.length,
                  onReorderItem: (oldIndex, newIndex) => ref
                      .read(appControllerProvider.notifier)
                      .reorderTeams(tournament.id, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final team = tournament.teams[index];
                    return Padding(
                      key: ValueKey(team.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TeamCard(
                        team: team,
                        index: index,
                        showPool:
                            tournament.format ==
                            TournamentFormat.poolsThenKnockout,
                        onEditTeam: () =>
                            _editTeam(context, ref, tournament, team),
                        onEditRoster: () => _editRoster(context, ref, team),
                      ),
                    );
                  },
                ),
        ),
        if (tournament.bracketEnabled)
          _Section(
            title: 'Knockout bracket',
            child: _BracketPanel(
              tournament: tournament,
              onGenerate: () => _generateBracket(context, ref, tournament),
              onAdvance: () => _advanceBracket(context, ref, tournament),
            ),
          ),
        _Section(
          title: 'All fixtures',
          child: tournament.games.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Generate a round robin or add teams first.'),
                )
              : Column(
                  children: tournament.games.map((game) {
                    final home = tournament.team(game.homeTeamId);
                    final away = tournament.team(game.awayTeamId);
                    final localLog = game.logs
                        .where((log) => log.deviceId == data.deviceId)
                        .firstOrNull;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        leading: Icon(
                          _statusIcon(game.status),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          '${home.name}  vs  ${away.name}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${DateFormat.MMMd().add_jm().format(game.scheduledAt)} • ${_gameLabel(game)} • best of ${tournament.rulesFor(game).maxSets} • ${game.status.name} • ${game.logs.length} scorer log(s)',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            if (game.status == GameStatus.finalized)
                              IconButton(
                                tooltip: 'Reconciliation summary',
                                onPressed: () => context.push(
                                  '/tournaments/$tournamentId/games/${game.id}/reconcile',
                                ),
                                icon: const Icon(Icons.fact_check_outlined),
                              )
                            else if (game.logs.length >= 2)
                              IconButton(
                                tooltip: 'Reconcile',
                                onPressed: () => context.push(
                                  '/tournaments/$tournamentId/games/${game.id}/reconcile',
                                ),
                                icon: const Icon(Icons.compare_arrows),
                              ),
                            if (game.status != GameStatus.finalized &&
                                game.status !=
                                    GameStatus.awaitingReconciliation)
                              IconButton(
                                tooltip: 'Track match',
                                onPressed: () => context.push(
                                  '/tournaments/$tournamentId/games/${game.id}/track',
                                ),
                                icon: const Icon(Icons.sports_volleyball),
                              ),
                            PopupMenuButton<String>(
                              tooltip: 'Game actions',
                              onSelected: (value) async {
                                if (value == 'export') {
                                  await _exportGame(
                                    context,
                                    data,
                                    tournament,
                                    game,
                                    localLog,
                                  );
                                } else if (value == 'delete') {
                                  await _deleteGame(
                                    context,
                                    ref,
                                    tournament,
                                    game,
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'export',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.ios_share),
                                    title: Text(
                                      localLog == null
                                          ? 'Export starter package'
                                          : 'Export scorer log',
                                    ),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.delete_outline,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                    title: Text(
                                      'Delete game',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  String _dateRange(Tournament tournament) {
    final start = DateFormat.yMMMd().format(tournament.startsOn);
    final end = DateFormat.yMMMd().format(tournament.endsOn);
    return start == end ? start : '$start – $end';
  }

  String _formatLabel(TournamentFormat format) => switch (format) {
    TournamentFormat.roundRobin => 'Round robin only',
    TournamentFormat.poolsThenKnockout => 'Pools → knockout',
    TournamentFormat.knockoutOnly => 'Knockout only',
  };

  String _poolLabel(int poolNumber) =>
      String.fromCharCode('A'.codeUnitAt(0) + poolNumber - 1);

  String _gameLabel(Game game) {
    if (game.stage == GameStage.pool) {
      return game.poolNumber == null
          ? 'round robin'
          : 'Pool ${_poolLabel(game.poolNumber!)}';
    }
    return switch (game.bracketType) {
      BracketGameType.finalMatch => 'Final',
      BracketGameType.thirdPlace => 'Third-place game',
      BracketGameType.standard => 'Knockout round ${game.bracketRound}',
    };
  }

  MatchRules _withBestOf(MatchRules rules, int bestOf) =>
      rules.copyWith(setsToWin: bestOf ~/ 2 + 1, maxSets: bestOf);

  Future<void> _editTournament(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
  ) async {
    final name = TextEditingController(text: tournament.name);
    final venue = TextEditingController(text: tournament.venue);
    var startsOn = tournament.startsOn;
    var endsOn = tournament.endsOn;
    var status = tournament.status;
    var format = tournament.format;
    var poolCount = tournament.poolCount;
    var qualifiersPerPool = tournament.qualifiersPerPool;
    var knockoutSize = tournament.knockoutSize;
    var thirdPlaceEnabled = tournament.thirdPlaceEnabled;
    var poolBestOf = tournament.effectivePoolRules.maxSets;
    var semifinalBestOf = tournament.effectiveSemifinalRules.maxSets;
    var finalBestOf = tournament.effectiveFinalRules.maxSets;
    var thirdPlaceBestOf = tournament.effectiveThirdPlaceRules.maxSets;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final validQualifiers = [
            for (final value in const [1, 2, 4])
              if ([2, 4, 8].contains(poolCount * value)) value,
          ];
          if (!validQualifiers.contains(qualifiersPerPool)) {
            qualifiersPerPool = validQualifiers.first;
          }
          final bracketSize = format == TournamentFormat.poolsThenKnockout
              ? poolCount * qualifiersPerPool
              : knockoutSize;
          return AlertDialog(
            title: const Text('Edit tournament'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    DropdownButtonFormField<TournamentStatus>(
                      initialValue: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: TournamentStatus.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => status = value!),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Tournament format',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<TournamentFormat>(
                      initialValue: format,
                      decoration: const InputDecoration(labelText: 'Format'),
                      items: TournamentFormat.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(_formatLabel(item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => format = value!),
                    ),
                    if (format == TournamentFormat.poolsThenKnockout) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: poolCount,
                              decoration: const InputDecoration(
                                labelText: 'Number of pools',
                              ),
                              items: const [1, 2, 4]
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text('$value'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => poolCount = value!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              key: ValueKey('qualifiers-$poolCount'),
                              initialValue: qualifiersPerPool,
                              decoration: const InputDecoration(
                                labelText: 'Qualifiers per pool',
                              ),
                              items: validQualifiers
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text('Top $value'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => qualifiersPerPool = value!),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (format == TournamentFormat.knockoutOnly) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: knockoutSize,
                        decoration: const InputDecoration(
                          labelText: 'Knockout teams',
                        ),
                        items: const [2, 4, 8]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value teams'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => knockoutSize = value!),
                      ),
                    ],
                    if (format != TournamentFormat.roundRobin &&
                        bracketSize >= 4)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable third-place game'),
                        subtitle: const Text(
                          'Semifinal losers play for third and fourth place.',
                        ),
                        value: thirdPlaceEnabled,
                        onChanged: (value) =>
                            setState(() => thirdPlaceEnabled = value),
                      ),
                    const Divider(height: 30),
                    Text(
                      'Match formats',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (format != TournamentFormat.knockoutOnly)
                      _BestOfField(
                        label: format == TournamentFormat.roundRobin
                            ? 'Round robin'
                            : 'Pool games',
                        value: poolBestOf,
                        onChanged: (value) =>
                            setState(() => poolBestOf = value),
                      ),
                    if (format != TournamentFormat.roundRobin &&
                        bracketSize >= 4)
                      _BestOfField(
                        label: bracketSize > 4
                            ? 'Knockout rounds / semifinals'
                            : 'Semifinals',
                        value: semifinalBestOf,
                        onChanged: (value) =>
                            setState(() => semifinalBestOf = value),
                      ),
                    if (format != TournamentFormat.roundRobin)
                      _BestOfField(
                        label: 'Final',
                        value: finalBestOf,
                        onChanged: (value) =>
                            setState(() => finalBestOf = value),
                      ),
                    if (format != TournamentFormat.roundRobin &&
                        thirdPlaceEnabled &&
                        bracketSize >= 4)
                      _BestOfField(
                        label: 'Third-place game',
                        value: thirdPlaceBestOf,
                        onChanged: (value) =>
                            setState(() => thirdPlaceBestOf = value),
                      ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start date'),
                      subtitle: Text(DateFormat.yMMMMd().format(startsOn)),
                      trailing: const Icon(Icons.calendar_month),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2040),
                          initialDate: startsOn,
                        );
                        if (picked != null) {
                          setState(() {
                            startsOn = picked;
                            if (endsOn.isBefore(startsOn)) endsOn = startsOn;
                          });
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('End date'),
                      subtitle: Text(DateFormat.yMMMMd().format(endsOn)),
                      trailing: const Icon(Icons.event_available),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: startsOn,
                          lastDate: DateTime(2040),
                          initialDate: endsOn.isBefore(startsOn)
                              ? startsOn
                              : endsOn,
                        );
                        if (picked != null) setState(() => endsOn = picked);
                      },
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
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Save changes'),
              ),
            ],
          );
        },
      ),
    );
    if (accepted != true) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .updateTournamentDetails(
            tournament.id,
            name: name.text,
            venue: venue.text,
            startsOn: startsOn,
            endsOn: endsOn,
            status: status,
            format: format,
            poolCount: poolCount,
            qualifiersPerPool: qualifiersPerPool,
            knockoutSize: knockoutSize,
            thirdPlaceEnabled: thirdPlaceEnabled,
            poolRules: _withBestOf(tournament.effectivePoolRules, poolBestOf),
            semifinalRules: _withBestOf(
              tournament.effectiveSemifinalRules,
              semifinalBestOf,
            ),
            finalRules: _withBestOf(
              tournament.effectiveFinalRules,
              finalBestOf,
            ),
            thirdPlaceRules: _withBestOf(
              tournament.effectiveThirdPlaceRules,
              thirdPlaceBestOf,
            ),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Tournament updated.')));
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _deleteTournament(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
  ) async {
    final confirmed = await confirmDeleteTournament(
      context,
      tournament: tournament,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .deleteTournament(tournament.id);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        context.go('/tournaments');
        messenger.showSnackBar(
          const SnackBar(content: Text('Tournament deleted.')),
        );
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _addTeam(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final code = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add tournament team'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Team name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                maxLength: 4,
                decoration: const InputDecoration(labelText: 'Short code'),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (accepted != true || name.text.trim().isEmpty) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .addTeam(
            tournamentId,
            name.text,
            code.text.isEmpty
                ? name.text.substring(0, name.text.length.clamp(1, 3))
                : code.text,
            Colors
                .primaries[ref
                        .read(appControllerProvider)
                        .tournaments
                        .firstWhere((t) => t.id == tournamentId)
                        .teams
                        .length %
                    Colors.primaries.length]
                .toARGB32(),
          );
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _editTeam(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
    TournamentTeam team,
  ) async {
    final name = TextEditingController(text: team.name);
    final code = TextEditingController(text: team.shortCode);
    var poolNumber = team.poolNumber.clamp(1, tournament.poolCount);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit team'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Team name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: code,
                  maxLength: 4,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Short code'),
                ),
                if (tournament.format ==
                    TournamentFormat.poolsThenKnockout) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: poolNumber,
                    decoration: const InputDecoration(labelText: 'Pool'),
                    items: [
                      for (
                        var value = 1;
                        value <= tournament.poolCount;
                        value++
                      )
                        DropdownMenuItem(
                          value: value,
                          child: Text('Pool ${_poolLabel(value)}'),
                        ),
                    ],
                    onChanged: (value) => setState(() => poolNumber = value!),
                  ),
                ],
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
              child: const Text('Save team'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .updateTeamDetails(
            tournamentId,
            team.id,
            name: name.text,
            shortCode: code.text,
            poolNumber: poolNumber,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Team updated.')));
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _editRoster(
    BuildContext context,
    WidgetRef ref,
    TournamentTeam team,
  ) async {
    final drafts = team.players.map(_RosterDraft.fromPlayer).toList();
    String? validationMessage;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Edit ${team.name} roster'),
          content: SizedBox(
            width: 720,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${drafts.length} player${drafts.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() {
                        drafts.add(_RosterDraft.empty());
                        validationMessage = null;
                      }),
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Add player'),
                    ),
                  ],
                ),
                if (validationMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  height: (MediaQuery.sizeOf(context).height * 0.5).clamp(
                    240.0,
                    430.0,
                  ),
                  child: drafts.isEmpty
                      ? const Center(
                          child: Text(
                            'This roster is empty. Use Add player to begin.',
                          ),
                        )
                      : ListView.separated(
                          itemCount: drafts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final draft = drafts[index];
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 82,
                                      child: TextField(
                                        controller: draft.number,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Number',
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 250,
                                      child: TextField(
                                        controller: draft.name,
                                        decoration: const InputDecoration(
                                          labelText: 'Player name',
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 110,
                                      child:
                                          DropdownButtonFormField<
                                            PlayerPosition
                                          >(
                                            initialValue: draft.position,
                                            decoration: const InputDecoration(
                                              labelText: 'Position',
                                            ),
                                            items: PlayerPosition.values
                                                .map(
                                                  (position) =>
                                                      DropdownMenuItem(
                                                        value: position,
                                                        child: Text(
                                                          position.name,
                                                        ),
                                                      ),
                                                )
                                                .toList(),
                                            onChanged: (value) => setState(
                                              () => draft.position = value!,
                                            ),
                                          ),
                                    ),
                                    Tooltip(
                                      message: draft.isCaptain
                                          ? 'Team captain'
                                          : 'Set as captain',
                                      child: IconButton.filledTonal(
                                        onPressed: () => setState(() {
                                          final makeCaptain = !draft.isCaptain;
                                          for (final item in drafts) {
                                            item.isCaptain = false;
                                          }
                                          draft.isCaptain = makeCaptain;
                                        }),
                                        icon: Icon(
                                          draft.isCaptain
                                              ? Icons.star
                                              : Icons.star_border,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove player',
                                      onPressed: () => setState(() {
                                        final removed = drafts.removeAt(index);
                                        removed.dispose();
                                        validationMessage = null;
                                      }),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
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
              onPressed: () {
                final error = _validateRosterDrafts(drafts);
                if (error != null) {
                  setState(() => validationMessage = error);
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save roster'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) {
      for (final draft in drafts) {
        draft.dispose();
      }
      return;
    }
    final players = drafts
        .map(
          (draft) => Player(
            id: draft.id,
            number: int.parse(draft.number.text),
            name: draft.name.text.trim(),
            position: draft.position,
            isCaptain: draft.isCaptain,
          ),
        )
        .toList();
    for (final draft in drafts) {
      draft.dispose();
    }
    try {
      await ref
          .read(appControllerProvider.notifier)
          .replaceTeamRoster(tournamentId, team.id, players);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Roster updated.')));
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  String? _validateRosterDrafts(List<_RosterDraft> drafts) {
    final numbers = <int>{};
    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      if (draft.name.text.trim().isEmpty) {
        return 'Player ${index + 1} needs a name.';
      }
      final number = int.tryParse(draft.number.text);
      if (number == null || number < 0) {
        return '${draft.name.text.trim()} needs a valid non-negative jersey number.';
      }
      if (!numbers.add(number)) {
        return 'Jersey number $number is assigned more than once.';
      }
    }
    return null;
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(appControllerProvider.notifier)
          .generateRoundRobin(tournamentId);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _generateBracket(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
  ) async {
    try {
      await ref
          .read(appControllerProvider.notifier)
          .generateBracket(tournament.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bracket generated from pool standings.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _advanceBracket(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
  ) async {
    try {
      await ref
          .read(appControllerProvider.notifier)
          .advanceBracket(tournament.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Next bracket round generated.')),
        );
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _addGame(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
  ) async {
    var homeId = tournament.teams.first.id;
    var awayId = tournament.teams[1].id;
    var scheduledAt = tournament.startsOn.add(const Duration(hours: 9));
    final venue = TextEditingController(text: tournament.venue);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add game'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: homeId,
                  decoration: const InputDecoration(labelText: 'Home team'),
                  items: tournament.teams
                      .map(
                        (team) => DropdownMenuItem(
                          value: team.id,
                          child: Text(team.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => homeId = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: awayId,
                  decoration: const InputDecoration(labelText: 'Away team'),
                  items: tournament.teams
                      .map(
                        (team) => DropdownMenuItem(
                          value: team.id,
                          child: Text(team.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => awayId = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: venue,
                  decoration: const InputDecoration(labelText: 'Venue'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Scheduled date'),
                  subtitle: Text(DateFormat.yMMMd().format(scheduledAt)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                      initialDate: scheduledAt,
                    );
                    if (date != null) {
                      setState(
                        () => scheduledAt = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          scheduledAt.hour,
                          scheduledAt.minute,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Scheduled time'),
                  subtitle: Text(DateFormat.jm().format(scheduledAt)),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(scheduledAt),
                    );
                    if (time != null) {
                      setState(
                        () => scheduledAt = DateTime(
                          scheduledAt.year,
                          scheduledAt.month,
                          scheduledAt.day,
                          time.hour,
                          time.minute,
                        ),
                      );
                    }
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
              child: const Text('Add game'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .addGame(
            tournament.id,
            homeTeamId: homeId,
            awayTeamId: awayId,
            scheduledAt: scheduledAt,
            venue: venue.text,
          );
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _editRules(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
  ) async {
    final sets = TextEditingController(text: '${tournament.rules.setsToWin}');
    final regular = TextEditingController(
      text: '${tournament.rules.regularSetTarget}',
    );
    final deciding = TextEditingController(
      text: '${tournament.rules.decidingSetTarget}',
    );
    final winBy = TextEditingController(text: '${tournament.rules.winBy}');
    final clearWin = TextEditingController(
      text: '${tournament.rules.standings.clearWinPoints}',
    );
    final decidingWin = TextEditingController(
      text: '${tournament.rules.standings.decidingWinPoints}',
    );
    final decidingLoss = TextEditingController(
      text: '${tournament.rules.standings.decidingLossPoints}',
    );
    final clearLoss = TextEditingController(
      text: '${tournament.rules.standings.clearLossPoints}',
    );
    final tieBreakers = [...tournament.rules.standings.tieBreakers];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Scoring & standings rules'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _NumberField(controller: sets, label: 'Sets to win'),
                      _NumberField(
                        controller: regular,
                        label: 'Regular target',
                      ),
                      _NumberField(
                        controller: deciding,
                        label: 'Deciding target',
                      ),
                      _NumberField(controller: winBy, label: 'Win by'),
                      _NumberField(
                        controller: clearWin,
                        label: 'Clear win pts',
                      ),
                      _NumberField(
                        controller: decidingWin,
                        label: 'Deciding win pts',
                      ),
                      _NumberField(
                        controller: decidingLoss,
                        label: 'Deciding loss pts',
                      ),
                      _NumberField(
                        controller: clearLoss,
                        label: 'Clear loss pts',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tie-break priority (drag to reorder)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height: 230,
                    child: ReorderableListView(
                      shrinkWrap: true,
                      onReorderItem: (oldIndex, newIndex) => setState(() {
                        tieBreakers.insert(
                          newIndex,
                          tieBreakers.removeAt(oldIndex),
                        );
                      }),
                      children: [
                        for (final item in tieBreakers)
                          ListTile(
                            key: ValueKey(item),
                            title: Text(item),
                            trailing: const Icon(Icons.drag_handle),
                          ),
                      ],
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save rules'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      final setsToWin = int.parse(sets.text);
      await ref
          .read(appControllerProvider.notifier)
          .updateRules(
            tournament.id,
            MatchRules(
              setsToWin: setsToWin,
              maxSets: setsToWin * 2 - 1,
              regularSetTarget: int.parse(regular.text),
              decidingSetTarget: int.parse(deciding.text),
              winBy: int.parse(winBy.text),
              standings: StandingsPolicy(
                clearWinPoints: int.parse(clearWin.text),
                decidingWinPoints: int.parse(decidingWin.text),
                decidingLossPoints: int.parse(decidingLoss.text),
                clearLossPoints: int.parse(clearLoss.text),
                tieBreakers: tieBreakers,
              ),
            ),
          );
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _exportGame(
    BuildContext context,
    AppData data,
    Tournament tournament,
    Game game,
    ScorerLog? log,
  ) async {
    try {
      await const FileExchangeService().exportGame(data, tournament, game, log);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Game package exported.')));
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  Future<void> _deleteGame(
    BuildContext context,
    WidgetRef ref,
    Tournament tournament,
    Game game,
  ) async {
    final confirmed = await confirmDeleteGame(
      context,
      tournament: tournament,
      game: game,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .deleteGame(tournament.id, game.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Game deleted.')));
      }
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  IconData _statusIcon(GameStatus status) => switch (status) {
    GameStatus.scheduled => Icons.schedule,
    GameStatus.inProgress => Icons.play_circle_outline,
    GameStatus.awaitingReconciliation => Icons.compare_arrows,
    GameStatus.finalized => Icons.verified,
  };
}

class _BracketPanel extends StatelessWidget {
  const _BracketPanel({
    required this.tournament,
    required this.onGenerate,
    required this.onAdvance,
  });

  final Tournament tournament;
  final VoidCallback onGenerate;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final games =
        tournament.games
            .where((game) => game.stage == GameStage.bracket)
            .toList()
          ..sort((a, b) {
            final round = (a.bracketRound ?? 0).compareTo(b.bracketRound ?? 0);
            return round != 0
                ? round
                : (a.bracketOrder ?? 0).compareTo(b.bracketOrder ?? 0);
          });
    if (games.isEmpty) {
      final prerequisite = tournament.format == TournamentFormat.knockoutOnly
          ? 'Teams are seeded using their order in the tournament team list.'
          : 'Finalize every pool game first. Qualifiers are selected independently from each pool.';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Expanded(child: Text(prerequisite)),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.account_tree_outlined),
                label: Text('Generate ${tournament.bracketSize}-team bracket'),
              ),
            ],
          ),
        ),
      );
    }
    final mainGames = games
        .where((game) => game.bracketType != BracketGameType.thirdPlace)
        .toList();
    final thirdPlaceGames = games
        .where((game) => game.bracketType == BracketGameType.thirdPlace)
        .toList();
    final rounds = <int, List<Game>>{};
    for (final game in mainGames) {
      rounds.putIfAbsent(game.bracketRound ?? 1, () => []).add(game);
    }
    final currentRound = rounds.keys.reduce((a, b) => a > b ? a : b);
    final currentGames = rounds[currentRound]!;
    final finalGame = mainGames
        .where((game) => game.bracketType == BracketGameType.finalMatch)
        .firstOrNull;
    final bracketComplete =
        finalGame != null &&
        finalGame.status == GameStatus.finalized &&
        finalGame.officialLog != null;
    final canAdvance =
        finalGame == null &&
        currentGames.length > 1 &&
        currentGames.every(
          (game) =>
              game.status == GameStatus.finalized && game.officialLog != null,
        );
    TournamentTeam? champion;
    if (bracketComplete) {
      final score = const ScoringEngine().score(
        finalGame,
        finalGame.officialLog!,
        tournament.rulesFor(finalGame),
      );
      final winnerId = score.homeSets > score.awaySets
          ? finalGame.homeTeamId
          : finalGame.awayTeamId;
      champion = tournament.team(winnerId);
    }
    TournamentTeam? thirdPlace;
    final thirdGame = thirdPlaceGames.firstOrNull;
    if (thirdGame?.status == GameStatus.finalized &&
        thirdGame?.officialLog != null) {
      final score = const ScoringEngine().score(
        thirdGame!,
        thirdGame.officialLog!,
        tournament.rulesFor(thirdGame),
      );
      thirdPlace = tournament.team(
        score.homeSets > score.awaySets
            ? thirdGame.homeTeamId
            : thirdGame.awayTeamId,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in rounds.entries) ...[
          Row(
            children: [
              Text(
                _roundName(entry.value),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Expanded(child: Divider(indent: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: entry.value.map((game) {
              final home = tournament.team(game.homeTeamId);
              final away = tournament.team(game.awayTeamId);
              return SizedBox(
                width: 280,
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text('${home.shortCode} vs ${away.shortCode}'),
                    subtitle: Text(
                      'Best of ${tournament.rulesFor(game).maxSets} • ${game.status.name}',
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
        ],
        if (thirdGame != null) ...[
          Row(
            children: [
              Text(
                'Third-place game',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Expanded(child: Divider(indent: 12)),
            ],
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.military_tech_outlined),
              title: Text(
                '${tournament.team(thirdGame.homeTeamId).shortCode} vs ${tournament.team(thirdGame.awayTeamId).shortCode}',
              ),
              subtitle: Text(
                'Best of ${tournament.rulesFor(thirdGame).maxSets} • ${thirdGame.status.name}',
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (bracketComplete)
          Column(
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.emoji_events),
                  title: const Text('Tournament champion'),
                  subtitle: Text(champion!.name),
                ),
              ),
              if (thirdPlace != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.military_tech),
                    title: const Text('Third place'),
                    subtitle: Text(thirdPlace.name),
                  ),
                ),
            ],
          )
        else if (finalGame != null)
          const Text('Finalize the championship match to name the champion.')
        else
          Row(
            children: [
              FilledButton.icon(
                onPressed: canAdvance ? onAdvance : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Generate next round'),
              ),
              if (!canAdvance) ...[
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Finalize every game in the current round to advance.',
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  String _roundName(List<Game> games) =>
      games.any((game) => game.bracketType == BracketGameType.finalMatch)
      ? 'Final'
      : switch (games.length) {
          2 => 'Semifinals',
          4 => 'Quarterfinals',
          _ => 'Knockout round ${games.first.bracketRound}',
        };
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
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
  );
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.index,
    required this.showPool,
    required this.onEditTeam,
    required this.onEditRoster,
  });

  final TournamentTeam team;
  final int index;
  final bool showPool;
  final VoidCallback onEditTeam;
  final VoidCallback onEditRoster;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: const MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.drag_indicator),
          ),
        ),
      ),
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: Color(team.colorValue),
            child: Text(
              team.shortCode,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              team.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '${showPool ? 'Pool ${String.fromCharCode('A'.codeUnitAt(0) + team.poolNumber - 1)} • ' : ''}${team.players.length} rostered player${team.players.length == 1 ? '' : 's'}',
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            onPressed: onEditTeam,
            tooltip: 'Edit team name and short code',
            icon: const Icon(Icons.drive_file_rename_outline),
          ),
          IconButton(
            onPressed: onEditRoster,
            tooltip: 'Edit roster',
            icon: const Icon(Icons.groups_outlined),
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      children: [
        const Divider(),
        if (team.players.isEmpty)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('No players yet'),
          )
        else
          ...team.players.map(
            (player) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      '#${player.number}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(child: Text(player.name)),
                        if (player.isCaptain) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.star,
                            size: 16,
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    player.position.name,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _BestOfField extends StatelessWidget {
  const _BestOfField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<int>(
      initialValue: switch (value) {
        1 => 1,
        3 => 3,
        _ => 5,
      },
      decoration: InputDecoration(labelText: label),
      items: const [
        DropdownMenuItem(value: 1, child: Text('One set')),
        DropdownMenuItem(value: 3, child: Text('Best of 3')),
        DropdownMenuItem(value: 5, child: Text('Best of 5')),
      ],
      onChanged: (value) => onChanged(value!),
    ),
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 118,
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

class _RosterDraft {
  _RosterDraft({
    required this.id,
    required this.number,
    required this.name,
    required this.position,
    required this.isCaptain,
  });

  factory _RosterDraft.fromPlayer(Player player) => _RosterDraft(
    id: player.id,
    number: TextEditingController(text: '${player.number}'),
    name: TextEditingController(text: player.name),
    position: player.position,
    isCaptain: player.isCaptain,
  );

  factory _RosterDraft.empty() => _RosterDraft(
    id: const Uuid().v4(),
    number: TextEditingController(),
    name: TextEditingController(),
    position: PlayerPosition.U,
    isCaptain: false,
  );

  final String id;
  final TextEditingController number;
  final TextEditingController name;
  PlayerPosition position;
  bool isCaptain;

  void dispose() {
    number.dispose();
    name.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
