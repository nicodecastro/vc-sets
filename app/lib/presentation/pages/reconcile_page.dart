import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../../domain/reconciliation.dart';
import '../../domain/scoring.dart';
import '../widgets/common.dart';

String _rallySummary(Rally? rally, Tournament tournament) {
  if (rally == null) return 'Missing rally';
  final actions = rally.actions
      .map((action) => action.notation(tournament.team(action.teamId)))
      .join('  ');
  return '${rally.homeScore}-${rally.awayScore} • ${actions.isEmpty ? 'No actions recorded' : actions}';
}

class ReconcilePage extends ConsumerStatefulWidget {
  const ReconcilePage({
    super.key,
    required this.tournamentId,
    required this.gameId,
  });
  final String tournamentId;
  final String gameId;
  @override
  ConsumerState<ReconcilePage> createState() => _ReconcilePageState();
}

class _ReconcilePageState extends ConsumerState<ReconcilePage> {
  final choices = <String, bool>{};
  final rallyOverrides = <String, Rally>{};
  bool saving = false;
  bool showManualOverrides = false;
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appControllerProvider);
    final tournament = data.tournaments.firstWhere(
      (item) => item.id == widget.tournamentId,
    );
    final game = tournament.games.firstWhere(
      (item) => item.id == widget.gameId,
    );
    if (game.status == GameStatus.finalized) {
      final comparison = game.logs.length < 2
          ? null
          : const ReconciliationService().compare(game.logs[0], game.logs[1]);
      return _FinalizedReconciliationSummary(
        tournament: tournament,
        game: game,
        comparison: comparison,
      );
    }
    if (game.logs.length < 2) {
      return Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          title: const Text('Reconcile'),
        ),
        body: const EmptyState(
          icon: Icons.compare_arrows,
          title: 'Second scorer log needed',
          message: 'Import the other team device’s .vcgame package first.',
        ),
      );
    }
    final comparison = const ReconciliationService().compare(
      game.logs[0],
      game.logs[1],
    );
    final home = tournament.team(game.homeTeamId);
    final away = tournament.team(game.awayTeamId);
    final rules = tournament.rulesFor(game);
    final allResolved = comparison.conflicts.every(
      (conflict) => choices.containsKey(conflict.key),
    );
    final preview = const ReconciliationService().merge(
      comparison,
      preferImported: choices.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toSet(),
      officialLogId: 'preview',
      now: DateTime.now(),
      rallyOverrides: rallyOverrides,
    );
    final incompleteReason = const ScoringEngine().incompleteMatchReason(
      game,
      preview,
      tournament.rulesFor(game),
    );
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('Reconcile ${home.shortCode} vs ${away.shortCode}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              color: comparison.conflicts.isEmpty
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      comparison.conflicts.isEmpty
                          ? Icons.check_circle
                          : Icons.rule,
                      size: 34,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comparison.conflicts.isEmpty
                                ? 'The independent score streams agree'
                                : '${comparison.conflicts.length} decision(s) required',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            'Player actions from both assigned teams are combined automatically. Choose the authoritative score wherever the devices differ.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...comparison.conflicts.map(
              (conflict) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conflict.message,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        RadioGroup<bool>(
                          groupValue: choices[conflict.key],
                          onChanged: (value) =>
                              setState(() => choices[conflict.key] = value!),
                          child: Row(
                            children: [
                              Expanded(
                                child: RadioListTile<bool>(
                                  value: false,
                                  title: const Text('Device A'),
                                  subtitle: Text(
                                    _rallySummary(conflict.primary, tournament),
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<bool>(
                                  value: true,
                                  title: const Text('Device B'),
                                  subtitle: Text(
                                    _rallySummary(
                                      conflict.imported,
                                      tournament,
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<int>(
                  key: ValueKey('match-format-${rules.maxSets}'),
                  initialValue: rules.maxSets,
                  decoration: const InputDecoration(
                    labelText: 'Game match format',
                    helperText: 'Changes this game only.',
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('One set')),
                    DropdownMenuItem(value: 3, child: Text('Best of 3')),
                    DropdownMenuItem(value: 5, child: Text('Best of 5')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) async {
                          if (value == null || value == rules.maxSets) return;
                          try {
                            await ref
                                .read(appControllerProvider.notifier)
                                .updateGameMatchFormat(
                                  widget.tournamentId,
                                  widget.gameId,
                                  value,
                                );
                          } catch (error) {
                            if (context.mounted) showError(context, error);
                          }
                        },
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (incompleteReason != null) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'The reconciled match is incomplete',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(incompleteReason),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: preview.rallies.isEmpty
                  ? null
                  : () => setState(
                      () => showManualOverrides = !showManualOverrides,
                    ),
              icon: const Icon(Icons.tune),
              label: Text(
                'Manual override${rallyOverrides.isEmpty ? '' : ' (${rallyOverrides.length})'}',
              ),
            ),
            if (showManualOverrides) ...[
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.edit_note),
                      title: Text('Edit individual rallies'),
                      subtitle: Text(
                        'Change the winner, score, and recorded actions. Every override requires a reason.',
                      ),
                    ),
                    const Divider(height: 1),
                    for (final rally in preview.rallies)
                      ListTile(
                        title: Text(
                          'Set ${rally.setNumber} • Rally ${rally.sequence} • ${rally.homeScore}-${rally.awayScore}',
                        ),
                        subtitle: Text(
                          rally.actions.isEmpty
                              ? 'No actions recorded'
                              : rally.actions
                                    .map(
                                      (action) => action.notation(
                                        tournament.team(action.teamId),
                                      ),
                                    )
                                    .join('  '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (rallyOverrides.containsKey(rally.alignmentKey))
                              IconButton(
                                tooltip: 'Reset override',
                                onPressed: () => setState(
                                  () =>
                                      rallyOverrides.remove(rally.alignmentKey),
                                ),
                                icon: const Icon(Icons.restart_alt),
                              ),
                            IconButton(
                              tooltip: 'Edit rally',
                              onPressed: () =>
                                  _editRally(tournament, game, rally),
                              icon: const Icon(Icons.edit),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: !allResolved || saving || incompleteReason != null
                  ? null
                  : () => _finalize(comparison),
              icon: const Icon(Icons.verified),
              label: Text(saving ? 'Finalizing…' : 'Finalize official match'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Finalization creates a historical revision. Tournament totals and standings use only this official combined record.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRally(Tournament tournament, Game game, Rally rally) async {
    final home = tournament.team(game.homeTeamId);
    final away = tournament.team(game.awayTeamId);
    var homeScoreText = '${rally.homeScore}';
    var awayScoreText = '${rally.awayScore}';
    var reasonText = rally.overrideReason ?? '';
    var winnerTeamId = rally.winnerTeamId;
    var actions = rally.actions
        .map(
          (action) => _RawActionDraft.fromAction(
            action,
            tournament.team(action.teamId),
          ),
        )
        .toList();
    void updateTeamActions(String teamId, String text) {
      final existing = actions
          .where((action) => action.teamId == teamId)
          .toList();
      final updated = <_RawActionDraft>[];
      final lines = text.split('\n');
      for (var index = 0; index < lines.length; index++) {
        final action = index < existing.length
            ? existing[index]
            : _RawActionDraft.empty(teamId);
        action.raw = lines[index];
        updated.add(action);
      }
      final other = actions.where((action) => action.teamId != teamId);
      actions = teamId == home.id
          ? [...updated, ...other]
          : [...other, ...updated];
    }

    String? validationError;
    final result = await showDialog<Rally>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Override set ${rally.setNumber}, rally ${rally.sequence}',
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: winnerTeamId,
                    decoration: const InputDecoration(
                      labelText: 'Rally winner',
                    ),
                    items: [
                      DropdownMenuItem(value: home.id, child: Text(home.name)),
                      DropdownMenuItem(value: away.id, child: Text(away.name)),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => winnerTeamId = value!),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final fieldWidth = constraints.maxWidth < 500
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                              initialValue: homeScoreText,
                              onChanged: (value) => homeScoreText = value,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '${home.shortCode} score',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                              initialValue: awayScoreText,
                              onChanged: (value) => awayScoreText = value,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: '${away.shortCode} score',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: reasonText,
                    onChanged: (value) => reasonText = value,
                    decoration: const InputDecoration(
                      labelText: 'Override reason',
                      hintText: 'Required',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Rally actions',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Type raw notation such as R10, S11, A17+, OP+, or T-.',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _RawActionColumn(
                          teamId: home.id,
                          title: 'Team 1 • ${home.shortCode}',
                          actions: actions
                              .where((action) => action.teamId == home.id)
                              .toList(),
                          onChanged: (text) => updateTeamActions(home.id, text),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RawActionColumn(
                          teamId: away.id,
                          title: 'Team 2 • ${away.shortCode}',
                          actions: actions
                              .where((action) => action.teamId == away.id)
                              .toList(),
                          onChanged: (text) => updateTeamActions(away.id, text),
                        ),
                      ),
                    ],
                  ),
                  if (validationError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsedHome = int.tryParse(homeScoreText.trim());
                final parsedAway = int.tryParse(awayScoreText.trim());
                if (parsedHome == null ||
                    parsedAway == null ||
                    parsedHome < 0 ||
                    parsedAway < 0) {
                  setDialogState(
                    () => validationError =
                        'Both scores must be zero or greater.',
                  );
                  return;
                }
                if (reasonText.trim().isEmpty) {
                  setDialogState(
                    () => validationError = 'An override reason is required.',
                  );
                  return;
                }
                late final List<TeamAction> parsedActions;
                try {
                  parsedActions = actions
                      .where((action) => action.raw.trim().isNotEmpty)
                      .map(
                        (action) =>
                            action.toAction(tournament.team(action.teamId)),
                      )
                      .toList();
                } on FormatException catch (error) {
                  setDialogState(() => validationError = error.message);
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  Rally(
                    id: rally.id,
                    setNumber: rally.setNumber,
                    sequence: rally.sequence,
                    winnerTeamId: winnerTeamId,
                    homeScore: parsedHome,
                    awayScore: parsedAway,
                    homeRotation: rally.homeRotation,
                    awayRotation: rally.awayRotation,
                    servingTeamId: winnerTeamId,
                    recordedAt: rally.recordedAt,
                    actions: parsedActions,
                    overrideReason: reasonText.trim(),
                    correctionOf: rally.correctionOf,
                  ),
                );
              },
              child: const Text('Save override'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => rallyOverrides[result.alignmentKey] = result);
    }
  }

  Future<void> _finalize(ReconciliationResult result) async {
    setState(() => saving = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .finalizeReconciliation(
            widget.tournamentId,
            widget.gameId,
            preferImported: choices.entries
                .where((entry) => entry.value)
                .map((entry) => entry.key)
                .toSet(),
            reason: rallyOverrides.isEmpty
                ? 'Initial two-device reconciliation'
                : 'Initial two-device reconciliation with ${rallyOverrides.length} manual override(s)',
            rallyOverrides: rallyOverrides,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match finalized and tournament totals updated.'),
          ),
        );
        context.pop();
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _RawActionDraft {
  _RawActionDraft({
    required this.id,
    required this.teamId,
    required this.raw,
    required this.recordedAt,
    this.note,
    this.metadata = const {},
  });

  factory _RawActionDraft.fromAction(TeamAction action, TournamentTeam team) =>
      _RawActionDraft(
        id: action.id,
        teamId: action.teamId,
        raw: action.notation(team),
        recordedAt: action.recordedAt,
        note: action.note,
        metadata: action.metadata,
      );

  factory _RawActionDraft.empty(String teamId) => _RawActionDraft(
    id: const Uuid().v4(),
    teamId: teamId,
    raw: '',
    recordedAt: DateTime.now(),
  );

  final String id;
  final String teamId;
  String raw;
  final DateTime recordedAt;
  final String? note;
  final Map<String, Object?> metadata;

  TeamAction toAction(TournamentTeam team) {
    final value = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (value == 'OP+' || value == 'T-') {
      return TeamAction(
        id: id,
        teamId: teamId,
        skill: value == 'OP+' ? Skill.opponentError : Skill.teamFault,
        grade: value == 'OP+' ? ActionGrade.success : ActionGrade.error,
        recordedAt: recordedAt,
        note: note,
        metadata: metadata,
      );
    }

    final codes = <String, Skill>{
      'SUB': Skill.substitution,
      'TO': Skill.timeout,
      'V': Skill.serve,
      'A': Skill.attack,
      'B': Skill.block,
      'S': Skill.set,
      'R': Skill.reception,
      'D': Skill.dig,
      'E': Skill.error,
    };
    final code = codes.keys.where(value.startsWith).firstOrNull;
    if (code == null) {
      throw FormatException('${team.shortCode}: "$raw" is not valid notation.');
    }
    final skill = codes[code]!;
    final suffix = value.endsWith('+')
        ? '+'
        : value.endsWith('-')
        ? '-'
        : '';
    final numberText = value.substring(
      code.length,
      value.length - suffix.length,
    );
    final needsPlayer = skill != Skill.substitution && skill != Skill.timeout;
    final playerNumber = int.tryParse(numberText);
    final player = playerNumber == null
        ? null
        : team.players.where((item) => item.number == playerNumber).firstOrNull;
    if (needsPlayer && player == null) {
      throw FormatException(
        '${team.shortCode}: "$raw" needs a valid roster number.',
      );
    }
    if (!needsPlayer && numberText.isNotEmpty) {
      throw FormatException('${team.shortCode}: "$raw" is not valid notation.');
    }
    return TeamAction(
      id: id,
      teamId: teamId,
      playerId: player?.id,
      skill: skill,
      grade: switch (suffix) {
        '+' => ActionGrade.success,
        '-' => ActionGrade.error,
        _ => ActionGrade.attempt,
      },
      recordedAt: recordedAt,
      note: note,
      metadata: metadata,
    );
  }
}

class _RawActionColumn extends StatelessWidget {
  const _RawActionColumn({
    required this.teamId,
    required this.title,
    required this.actions,
    required this.onChanged,
  });

  final String teamId;
  final String title;
  final List<_RawActionDraft> actions;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      SizedBox(
        height: 220,
        child: TextFormField(
          key: ValueKey('raw-actions-$teamId'),
          initialValue: actions.map((action) => action.raw).join('\n'),
          expands: true,
          minLines: null,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'R10\nS11\nA17',
            alignLabelWithHint: true,
          ),
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

class _FinalizedReconciliationSummary extends StatelessWidget {
  const _FinalizedReconciliationSummary({
    required this.tournament,
    required this.game,
    required this.comparison,
  });

  final Tournament tournament;
  final Game game;
  final ReconciliationResult? comparison;

  @override
  Widget build(BuildContext context) {
    final home = tournament.team(game.homeTeamId);
    final away = tournament.team(game.awayTeamId);
    final revision = game.revisions.isEmpty ? null : game.revisions.last;
    final official = revision?.officialLog ?? game.officialLog;
    final setFinals = <int, Rally>{};
    for (final rally in official?.rallies ?? const <Rally>[]) {
      setFinals[rally.setNumber] = rally;
    }
    final orderedSets = setFinals.values.toList()
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
    final homeSets = orderedSets
        .where((rally) => rally.homeScore > rally.awayScore)
        .length;
    final awaySets = orderedSets.length - homeSets;
    final officialByKey = {
      for (final rally in official?.rallies ?? const <Rally>[])
        rally.alignmentKey: rally,
    };
    final conflicts = comparison?.conflicts ?? const <ReconciliationConflict>[];
    final sourceActions = game.logs
        .take(2)
        .map(
          (log) => log.rallies.fold<int>(
            0,
            (total, rally) => total + rally.actions.length,
          ),
        )
        .toList();
    final officialActions =
        official?.rallies.fold<int>(
          0,
          (total, rally) => total + rally.actions.length,
        ) ??
        0;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('Summary ${home.shortCode} vs ${away.shortCode}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified, size: 34),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Final result',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${home.shortCode} $homeSets–$awaySets ${away.shortCode}',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (orderedSets.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final rally in orderedSets)
                            Chip(
                              label: Text(
                                'Set ${rally.setNumber}: ${rally.homeScore}-${rally.awayScore}',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reconciliation summary',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${game.logs.length} scorer logs combined • ${conflicts.length} decision(s)',
                    ),
                    if (sourceActions.length >= 2)
                      Text(
                        'Actions: Device A ${sourceActions[0]} • Device B ${sourceActions[1]} • Official $officialActions',
                      ),
                    if (revision != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Finalized ${DateFormat.yMMMd().add_jm().format(revision.finalizedAt.toLocal())}',
                      ),
                      Text('Reason: ${revision.reason}'),
                      if (game.revisions.length > 1)
                        Text('Revision ${game.revisions.length}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (comparison == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'The original two-device comparison is not available for this finalized game.',
                  ),
                ),
              )
            else if (conflicts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'The score streams agreed. Player actions from both devices were combined automatically.',
                  ),
                ),
              )
            else ...[
              Text(
                'Decisions',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final conflict in conflicts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ReconciledDecisionCard(
                    tournament: tournament,
                    conflict: conflict,
                    officialRally: officialByKey[conflict.key],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReconciledDecisionCard extends StatelessWidget {
  const _ReconciledDecisionCard({
    required this.tournament,
    required this.conflict,
    required this.officialRally,
  });

  final Tournament tournament;
  final ReconciliationConflict conflict;
  final Rally? officialRally;

  @override
  Widget build(BuildContext context) {
    final selectedDevice = officialRally?.overrideReason != null
        ? 'Manual override'
        : officialRally?.id == conflict.imported?.id
        ? 'Device B'
        : 'Device A';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conflict.message,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Device A: ${_rallySummary(conflict.primary, tournament)}'),
            const SizedBox(height: 4),
            Text('Device B: ${_rallySummary(conflict.imported, tournament)}'),
            const SizedBox(height: 10),
            Chip(
              avatar: const Icon(Icons.check, size: 18),
              label: Text('Official: $selectedDevice'),
            ),
            if (officialRally?.overrideReason != null)
              Text('Override reason: ${officialRally!.overrideReason}'),
          ],
        ),
      ),
    );
  }
}
