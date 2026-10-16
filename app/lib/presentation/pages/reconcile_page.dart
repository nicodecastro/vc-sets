import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../../domain/reconciliation.dart';
import '../../domain/scoring.dart';
import '../../domain/statistics.dart';
import '../widgets/common.dart';

String _scoreLabel(Rally? rally) =>
    rally == null ? 'Missing rally' : '${rally.homeScore}-${rally.awayScore}';

List<TeamAction> _combinedActions(ReconciliationConflict conflict) => {
  for (final action in conflict.primary?.actions ?? const <TeamAction>[])
    action.id: action,
  for (final action in conflict.imported?.actions ?? const <TeamAction>[])
    action.id: action,
}.values.toList();

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
        onUndo: saving ? null : _undoReconciliation,
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
                                  title: Text(
                                    'Score ${_scoreLabel(conflict.primary)}',
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              Expanded(
                                child: RadioListTile<bool>(
                                  value: true,
                                  title: Text(
                                    'Score ${_scoreLabel(conflict.imported)}',
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _RawActionLists(
                          idPrefix: conflict.key,
                          home: home,
                          away: away,
                          actions: _combinedActions(conflict),
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

  Future<void> _undoReconciliation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Undo reconciliation?'),
        content: const Text(
          'This reopens the game and removes its official result from reports and standings until it is reconciled again. The previous revision remains in the audit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Undo reconciliation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .reopenGame(
            widget.tournamentId,
            widget.gameId,
            'Reconciliation undone from summary',
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reconciliation undone.')));
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
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

class _RawActionLists extends StatelessWidget {
  const _RawActionLists({
    required this.idPrefix,
    required this.home,
    required this.away,
    required this.actions,
  });

  final String idPrefix;
  final TournamentTeam home;
  final TournamentTeam away;
  final List<TeamAction> actions;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _box(home, 'Team 1 • ${home.shortCode}')),
      const SizedBox(width: 12),
      Expanded(child: _box(away, 'Team 2 • ${away.shortCode}')),
    ],
  );

  Widget _box(TournamentTeam team, String label) {
    final raw = actions
        .where((action) => action.teamId == team.id)
        .map((action) => action.notation(team))
        .join('\n');
    return SizedBox(
      height: 140,
      child: TextFormField(
        key: ValueKey('conflict-actions-$idPrefix-${team.id}'),
        initialValue: raw,
        readOnly: true,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'No actions',
          alignLabelWithHint: true,
        ),
      ),
    );
  }
}

class _FinalizedReconciliationSummary extends StatelessWidget {
  const _FinalizedReconciliationSummary({
    required this.tournament,
    required this.game,
    required this.comparison,
    required this.onUndo,
  });

  final Tournament tournament;
  final Game game;
  final ReconciliationResult? comparison;
  final VoidCallback? onUndo;

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
            if (game.officialLog != null) ...[
              _GamePlayerStatsCard(tournament: tournament, game: game),
              const SizedBox(height: 12),
            ],
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
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: onUndo,
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo reconciliation'),
                    ),
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
                    home: home,
                    away: away,
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

class _GamePlayerStatsCard extends StatefulWidget {
  const _GamePlayerStatsCard({required this.tournament, required this.game});

  final Tournament tournament;
  final Game game;

  @override
  State<_GamePlayerStatsCard> createState() => _GamePlayerStatsCardState();
}

class _GamePlayerStatsCardState extends State<_GamePlayerStatsCard> {
  String? selectedTeamId;
  int? selectedSetNumber;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final home = widget.tournament.team(game.homeTeamId);
    final away = widget.tournament.team(game.awayTeamId);
    final teamId = selectedTeamId == away.id ? away.id : home.id;
    final team = teamId == home.id ? home : away;
    final setNumbers =
        game.officialLog!.rallies
            .map((rally) => rally.setNumber)
            .toSet()
            .toList()
          ..sort();
    final setNumber = setNumbers.contains(selectedSetNumber)
        ? selectedSetNumber
        : null;
    final stats = const StatisticsService();
    final players = stats.gamePlayerStats(game, team, setNumber: setNumber);
    final teamSkills = stats.gameTeamSkillCounts(
      game,
      team.id,
      setNumber: setNumber,
    );
    final opponentErrors = stats.gameTeamActionCount(
      game,
      team.id,
      Skill.opponentError,
      setNumber: setNumber,
    );
    final teamFaults = stats.gameTeamActionCount(
      game,
      team.id,
      Skill.teamFault,
      setNumber: setNumber,
    );
    const skills = <String, String>{
      'Set': 'S',
      'Serve': 'V',
      'Dig': 'D',
      'Reception': 'R',
      'Attack': 'A',
      'Block': 'B',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Player stats',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Skill counts are ATT / EXC / ERR. PTS = V+ + A+ + B+. OP+ and T− are team totals.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: Text(home.shortCode),
                  selected: teamId == home.id,
                  onSelected: (_) => setState(() => selectedTeamId = home.id),
                ),
                ChoiceChip(
                  label: Text(away.shortCode),
                  selected: teamId == away.id,
                  onSelected: (_) => setState(() => selectedTeamId = away.id),
                ),
                DropdownButton<int?>(
                  value: setNumber,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All sets'),
                    ),
                    for (final number in setNumbers)
                      DropdownMenuItem<int?>(
                        value: number,
                        child: Text('Set $number'),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => selectedSetNumber = value),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Team totals: OP+ $opponentErrors  •  T− $teamFaults'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in skills.entries)
                  Chip(
                    label: Text(
                      '${entry.key} ${teamSkills[entry.value] ?? 0} / ${teamSkills['${entry.value}+'] ?? 0} / ${teamSkills['${entry.value}-'] ?? 0}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (players.isEmpty)
              const Text(
                'No player participation was recorded for this team and set.',
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  horizontalMargin: 8,
                  columns: [
                    const DataColumn(label: Text('#')),
                    const DataColumn(label: Text('Player')),
                    const DataColumn(label: Text('Sets')),
                    for (final skill in skills.keys)
                      DataColumn(label: Text(skill)),
                    const DataColumn(label: Text('PTS')),
                  ],
                  rows: [
                    for (final row in players)
                      DataRow(
                        cells: [
                          DataCell(Text('${row.player.number}')),
                          DataCell(Text(row.player.name)),
                          DataCell(Text('${row.setsPlayed}')),
                          for (final code in skills.values)
                            DataCell(
                              Text(
                                '${row.counts[code] ?? 0} / ${row.counts['$code+'] ?? 0} / ${row.counts['$code-'] ?? 0}',
                              ),
                            ),
                          DataCell(Text('${row.points}')),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReconciledDecisionCard extends StatelessWidget {
  const _ReconciledDecisionCard({
    required this.home,
    required this.away,
    required this.conflict,
    required this.officialRally,
  });

  final TournamentTeam home;
  final TournamentTeam away;
  final ReconciliationConflict conflict;
  final Rally? officialRally;

  @override
  Widget build(BuildContext context) {
    final officialChoice = officialRally?.overrideReason != null
        ? 'Manual override'
        : _scoreLabel(officialRally);
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
            Text('Option 1: ${_scoreLabel(conflict.primary)}'),
            const SizedBox(height: 4),
            Text('Option 2: ${_scoreLabel(conflict.imported)}'),
            const SizedBox(height: 10),
            _RawActionLists(
              idPrefix: 'summary-${conflict.key}',
              home: home,
              away: away,
              actions: officialRally?.actions ?? const [],
            ),
            const SizedBox(height: 10),
            Chip(
              avatar: const Icon(Icons.check, size: 18),
              label: Text('Official: $officialChoice'),
            ),
            if (officialRally?.overrideReason != null)
              Text('Override reason: ${officialRally!.overrideReason}'),
          ],
        ),
      ),
    );
  }
}
