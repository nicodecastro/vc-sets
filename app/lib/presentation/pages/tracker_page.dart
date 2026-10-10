import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../application/providers.dart';
import '../../domain/models.dart';
import '../../domain/scoring.dart';
import '../widgets/common.dart';

String _romanPosition(int position) =>
    const ['I', 'II', 'III', 'IV', 'V', 'VI'][position - 1];

class TrackerPage extends ConsumerStatefulWidget {
  const TrackerPage({
    super.key,
    required this.tournamentId,
    required this.gameId,
  });
  final String tournamentId;
  final String gameId;
  @override
  ConsumerState<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends ConsumerState<TrackerPage> {
  final pending = <TeamAction>[];
  String? selectedPlayerId;
  String? selectedLiberoId;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appControllerProvider);
    final tournament = data.tournaments.firstWhere(
      (item) => item.id == widget.tournamentId,
    );
    final game = tournament.games.firstWhere(
      (item) => item.id == widget.gameId,
    );
    final home = tournament.team(game.homeTeamId);
    final away = tournament.team(game.awayTeamId);
    final localLogs = game.logs.where((log) => log.deviceId == data.deviceId);
    if (localLogs.isEmpty) {
      return _AssignmentPage(
        tournament: tournament,
        game: game,
        home: home,
        away: away,
        onStart: (assigned, server) => ref
            .read(appControllerProvider.notifier)
            .startScorerLog(
              tournament.id,
              game.id,
              assignedTeamId: assigned,
              initialServingTeamId: server,
            ),
      );
    }
    final log = localLogs.first;
    final assigned = tournament.team(log.assignedTeamId);
    final score = const ScoringEngine().score(
      game,
      log,
      tournament.rulesFor(game),
    );
    final assignedRotation = assigned.id == game.homeTeamId
        ? score.homeRotation
        : score.awayRotation;
    final courtPlayerIds = log.courtOrderFor(
      assigned.id,
      score.setNumber,
      assignedRotation,
    );
    if (!courtPlayerIds.contains(selectedPlayerId)) {
      selectedPlayerId = courtPlayerIds.firstOrNull;
    }
    final liberos = assigned.players
        .where((player) => player.isLibero)
        .toList();
    if (!liberos.any((player) => player.id == selectedLiberoId)) {
      selectedLiberoId = liberos.firstOrNull?.id;
    }
    final setTimeouts = log.timeouts
        .where(
          (timeout) =>
              timeout.teamId == assigned.id &&
              timeout.setNumber == score.setNumber,
        )
        .length;
    final setSubstitutions = log.substitutions
        .where(
          (substitution) =>
              substitution.teamId == assigned.id &&
              substitution.setNumber == score.setNumber &&
              !substitution.isLiberoReplacement,
        )
        .length;
    final inferredWinner = const ScoringEngine().inferRallyWinner(
      game,
      assigned.id,
      pending,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('${home.shortCode} vs ${away.shortCode}'),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: const Icon(Icons.edit, size: 17),
              label: Text('Tracking ${assigned.shortCode}'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final splitLayout = constraints.maxWidth >= 760;
            final compact = splitLayout && constraints.maxWidth < 1200;
            final denseDesktopSkills = splitLayout && !compact;
            final scorePanel = _ScorePanel(
              home: home,
              away: away,
              score: score,
              disabled: score.isComplete,
            );
            final entryPanel = _EntryPanel(
              team: assigned,
              setNumber: score.setNumber,
              rotation: assignedRotation,
              courtPlayerIds: courtPlayerIds,
              selectedPlayerId: selectedPlayerId,
              timeoutsUsed: setTimeouts,
              substitutionsUsed: setSubstitutions,
              liberos: liberos,
              selectedLiberoId: selectedLiberoId,
              pending: pending,
              onPlayerChanged: (value) =>
                  setState(() => selectedPlayerId = value),
              onLiberoChanged: (value) =>
                  setState(() => selectedLiberoId = value),
              onAdd: _addAction,
              onRemove: (action) => setState(() => pending.remove(action)),
              onUndo: log.rallies.isEmpty ? null : _undo,
              onEditLineup: score.isComplete
                  ? null
                  : () => _editLineup(assigned, log, score),
              onSubstitution: score.isComplete || courtPlayerIds.length != 6
                  ? null
                  : () => _recordSubstitution(assigned, courtPlayerIds),
              onTimeout: score.isComplete || setTimeouts >= 2
                  ? null
                  : () => _recordTimeout(assigned, score),
              onLiberoSwap:
                  score.isComplete ||
                      selectedPlayerId == null ||
                      selectedLiberoId == null ||
                      courtPlayerIds.length != 6
                  ? null
                  : _recordLiberoSwap,
              onEnter: score.isComplete || inferredWinner == null
                  ? null
                  : () => _award(inferredWinner),
              compact: compact,
              denseSkillButtons: denseDesktopSkills,
            );
            final timeline = _Timeline(
              log: log,
              home: home,
              away: away,
              trackedTeam: assigned,
            );
            if (splitLayout) {
              return Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: ListView(
                      key: const ValueKey('tracker-entry-scroll'),
                      padding: EdgeInsets.all(compact ? 10 : 18),
                      children: [entryPanel],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: scorePanel,
                        ),
                        Expanded(child: timeline),
                      ],
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(14),
              children: [
                entryPanel,
                const SizedBox(height: 14),
                scorePanel,
                const SizedBox(height: 6),
                SizedBox(height: 420, child: timeline),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _editLineup(
    TournamentTeam team,
    ScorerLog log,
    MatchScore score,
  ) async {
    final existing = log.serviceOrderFor(team.id, score.setNumber);
    final selected = existing.length == 6
        ? [...existing]
        : team.players.take(6).map((player) => player.id).toList();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('R-5 lineup • Set ${score.setNumber}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tap a player on the court to open the roster dropdown for that position. Position I is the server/right-back position.',
                  ),
                  const SizedBox(height: 14),
                  if (team.players.length < 6)
                    const Text(
                      'Add at least six rostered players before completing the lineup sheet.',
                      style: TextStyle(color: Colors.deepOrange),
                    )
                  else
                    _R5LineupEditor(
                      team: team,
                      selectedPlayerIds: selected,
                      onPlayerSelected: (position, playerId) {
                        setDialogState(() {
                          final previousPlayerId = selected[position];
                          final previousPosition = selected.indexOf(playerId);
                          selected[position] = playerId;
                          if (previousPosition >= 0 &&
                              previousPosition != position) {
                            selected[previousPosition] = previousPlayerId;
                          }
                        });
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
              onPressed: team.players.length < 6
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Save lineup'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .setLineup(
            widget.tournamentId,
            widget.gameId,
            setNumber: score.setNumber,
            playerIds: selected,
          );
      if (mounted) {
        setState(() => selectedPlayerId = selected.first);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Set ${score.setNumber} lineup saved.')),
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _recordSubstitution(
    TournamentTeam team,
    List<String> courtPlayerIds,
  ) async {
    final bench = team.players
        .where((player) => !courtPlayerIds.contains(player.id))
        .toList();
    if (bench.isEmpty) {
      showError(context, StateError('There are no available bench players.'));
      return;
    }
    var outgoing = courtPlayerIds.contains(selectedPlayerId)
        ? selectedPlayerId!
        : courtPlayerIds.first;
    var incoming = bench.first.id;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record substitution'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: outgoing,
                  decoration: const InputDecoration(labelText: 'Player out'),
                  items: courtPlayerIds.map((id) {
                    final player = team.players.firstWhere(
                      (item) => item.id == id,
                    );
                    return DropdownMenuItem(
                      value: id,
                      child: Text('#${player.number} ${player.name}'),
                    );
                  }).toList(),
                  onChanged: (value) => setDialogState(() => outgoing = value!),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: incoming,
                  decoration: const InputDecoration(labelText: 'Player in'),
                  items: bench
                      .map(
                        (player) => DropdownMenuItem(
                          value: player.id,
                          child: Text('#${player.number} ${player.name}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => incoming = value!),
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
              child: const Text('Record substitution'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .recordSubstitution(
            widget.tournamentId,
            widget.gameId,
            playerOutId: outgoing,
            playerInId: incoming,
          );
      if (mounted) setState(() => selectedPlayerId = incoming);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _recordTimeout(TournamentTeam team, MatchScore score) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${team.shortCode} timeout'),
        content: Text(
          'Record a timeout in set ${score.setNumber} at ${score.homePoints}-${score.awayPoints}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Record timeout'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .recordTimeout(widget.tournamentId, widget.gameId);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _recordLiberoSwap() async {
    final playerId = selectedPlayerId;
    final liberoId = selectedLiberoId;
    if (playerId == null || liberoId == null) return;
    try {
      final incoming = await ref
          .read(appControllerProvider.notifier)
          .recordLiberoSwap(
            widget.tournamentId,
            widget.gameId,
            selectedPlayerId: playerId,
            liberoId: liberoId,
          );
      if (mounted) setState(() => selectedPlayerId = incoming);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  void _addAction(Skill skill, ActionGrade grade, TournamentTeam team) {
    final requiresPlayer =
        skill != Skill.timeout &&
        skill != Skill.substitution &&
        skill != Skill.opponentError &&
        skill != Skill.teamFault;
    if (requiresPlayer && selectedPlayerId == null) return;
    final next = TeamAction(
      id: const Uuid().v4(),
      teamId: team.id,
      playerId: requiresPlayer ? selectedPlayerId : null,
      skill: skill,
      grade: grade,
      recordedAt: DateTime.now(),
    );
    final composed = const RallyActionComposer().add(pending, next);
    setState(() {
      pending
        ..clear()
        ..addAll(composed);
    });
  }

  Future<void> _award(String teamId) async {
    try {
      await ref
          .read(appControllerProvider.notifier)
          .awardRally(
            widget.tournamentId,
            widget.gameId,
            winnerTeamId: teamId,
            actions: [...pending],
          );
      if (mounted) setState(pending.clear);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _undo() async {
    final reason = TextEditingController(text: 'Scoring correction');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Undo last rally'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Correction reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Undo'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await ref
          .read(appControllerProvider.notifier)
          .undoLastRally(widget.tournamentId, widget.gameId, reason.text);
    }
  }
}

class _AssignmentPage extends StatefulWidget {
  const _AssignmentPage({
    required this.tournament,
    required this.game,
    required this.home,
    required this.away,
    required this.onStart,
  });
  final Tournament tournament;
  final Game game;
  final TournamentTeam home;
  final TournamentTeam away;
  final Future<void> Function(String assigned, String server) onStart;
  @override
  State<_AssignmentPage> createState() => _AssignmentPageState();
}

class _AssignmentPageState extends State<_AssignmentPage> {
  late String assigned = widget.home.id;
  late String server = widget.home.id;
  bool working = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        onPressed: () => context.pop(),
        icon: const Icon(Icons.arrow_back),
      ),
      title: const Text('Set up scorer device'),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.devices, size: 48),
                  const SizedBox(height: 14),
                  Text(
                    'Which team is this device tracking?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Both devices score every rally. Player actions are limited to the selected team.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: widget.home.id,
                        label: Text(widget.home.name),
                      ),
                      ButtonSegment(
                        value: widget.away.id,
                        label: Text(widget.away.name),
                      ),
                    ],
                    selected: {assigned},
                    onSelectionChanged: (value) =>
                        setState(() => assigned = value.first),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'First serving team',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: widget.home.id,
                        label: Text(widget.home.shortCode),
                      ),
                      ButtonSegment(
                        value: widget.away.id,
                        label: Text(widget.away.shortCode),
                      ),
                    ],
                    selected: {server},
                    onSelectionChanged: (value) =>
                        setState(() => server = value.first),
                  ),
                  if (widget.tournament.team(assigned).players.length < 6) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Warning: this roster has fewer than six players. Tracking is allowed as an explicit operational override.',
                      style: TextStyle(color: Colors.deepOrange),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: working
                        ? null
                        : () async {
                            setState(() => working = true);
                            try {
                              await widget.onStart(assigned, server);
                            } finally {
                              if (mounted) setState(() => working = false);
                            }
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start scorer log'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ScorePanel extends StatelessWidget {
  const _ScorePanel({
    required this.home,
    required this.away,
    required this.score,
    required this.disabled,
  });
  final TournamentTeam home;
  final TournamentTeam away;
  final MatchScore score;
  final bool disabled;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                disabled ? 'MATCH COMPLETE' : 'SET ${score.setNumber}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Sets ${score.homeSets} – ${score.awaySets}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _TeamScore(
                  team: home,
                  points: score.homePoints,
                  rotation: score.homeRotation,
                  serving: score.servingTeamId == home.id,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '–',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Expanded(
                child: _TeamScore(
                  team: away,
                  points: score.awayPoints,
                  rotation: score.awayRotation,
                  serving: score.servingTeamId == away.id,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _TeamScore extends StatelessWidget {
  const _TeamScore({
    required this.team,
    required this.points,
    required this.rotation,
    required this.serving,
  });
  final TournamentTeam team;
  final int points;
  final int rotation;
  final bool serving;
  @override
  Widget build(BuildContext context) => Material(
    color: Color(team.colorValue).withValues(alpha: .12),
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (serving) const Icon(Icons.sports_volleyball, size: 18),
              if (serving) const SizedBox(width: 6),
              Flexible(
                child: Text(
                  team.shortCode,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Text(
            '$points',
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            'Rotation $rotation',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _EntryPanel extends StatelessWidget {
  const _EntryPanel({
    required this.team,
    required this.setNumber,
    required this.rotation,
    required this.courtPlayerIds,
    required this.selectedPlayerId,
    required this.timeoutsUsed,
    required this.substitutionsUsed,
    required this.liberos,
    required this.selectedLiberoId,
    required this.pending,
    required this.onPlayerChanged,
    required this.onLiberoChanged,
    required this.onAdd,
    required this.onRemove,
    required this.onUndo,
    required this.onEditLineup,
    required this.onSubstitution,
    required this.onTimeout,
    required this.onLiberoSwap,
    required this.onEnter,
    required this.compact,
    required this.denseSkillButtons,
  });
  final TournamentTeam team;
  final int setNumber;
  final int rotation;
  final List<String> courtPlayerIds;
  final String? selectedPlayerId;
  final int timeoutsUsed;
  final int substitutionsUsed;
  final List<Player> liberos;
  final String? selectedLiberoId;
  final List<TeamAction> pending;
  final ValueChanged<String?> onPlayerChanged;
  final ValueChanged<String?> onLiberoChanged;
  final void Function(Skill, ActionGrade, TournamentTeam) onAdd;
  final ValueChanged<TeamAction> onRemove;
  final VoidCallback? onUndo;
  final VoidCallback? onEditLineup;
  final VoidCallback? onSubstitution;
  final VoidCallback? onTimeout;
  final VoidCallback? onLiberoSwap;
  final VoidCallback? onEnter;
  final bool compact;
  final bool denseSkillButtons;
  @override
  Widget build(BuildContext context) {
    final outlinedStyle = compact
        ? OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            visualDensity: VisualDensity.compact,
          )
        : null;
    final tonalStyle = compact
        ? FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            visualDensity: VisualDensity.compact,
          )
        : null;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 10 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Player actions',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onUndo,
                  tooltip: 'Undo last rally',
                  icon: const Icon(Icons.undo),
                ),
              ],
            ),
            SizedBox(height: compact ? 4 : 10),
            _HalfCourt(
              team: team,
              playerIdsByPosition: courtPlayerIds,
              selectedPlayerId: selectedPlayerId,
              onSelected: onPlayerChanged,
              compact: compact,
            ),
            SizedBox(height: compact ? 6 : 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final tight = constraints.maxWidth < 720;
                Widget firstRowButton({
                  required VoidCallback? onPressed,
                  required IconData icon,
                  required String label,
                  required String tightLabel,
                }) => Expanded(
                  child: tight
                      ? OutlinedButton(
                          onPressed: onPressed,
                          style: outlinedStyle,
                          child: Text(tightLabel),
                        )
                      : OutlinedButton.icon(
                          onPressed: onPressed,
                          style: outlinedStyle,
                          icon: Icon(icon),
                          label: Text(label),
                        ),
                );
                return Column(
                  children: [
                    Row(
                      children: [
                        firstRowButton(
                          onPressed: onEditLineup,
                          icon: Icons.format_list_numbered,
                          label: 'R-5 lineup • Set $setNumber',
                          tightLabel: 'R-5 • Set $setNumber',
                        ),
                        const SizedBox(width: 8),
                        firstRowButton(
                          onPressed: onSubstitution,
                          icon: Icons.swap_horiz,
                          label: 'Substitution ($substitutionsUsed)',
                          tightLabel: 'Subs ($substitutionsUsed)',
                        ),
                        const SizedBox(width: 8),
                        firstRowButton(
                          onPressed: onTimeout,
                          icon: Icons.timer_outlined,
                          label: 'Timeout ($timeoutsUsed/2)',
                          tightLabel: 'Timeout ($timeoutsUsed/2)',
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 6 : 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('libero-$selectedLiberoId'),
                            initialValue: selectedLiberoId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Libero',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: compact ? 8 : 12,
                                vertical: compact ? 6 : 10,
                              ),
                            ),
                            hint: const Text('No libero'),
                            items: liberos
                                .map(
                                  (player) => DropdownMenuItem(
                                    value: player.id,
                                    child: Text(
                                      '#${player.number} ${player.name}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: liberos.isEmpty ? null : onLiberoChanged,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (tight)
                          FilledButton.tonal(
                            onPressed: onLiberoSwap,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Quick swap'),
                          )
                        else
                          FilledButton.tonalIcon(
                            onPressed: onLiberoSwap,
                            style: tonalStyle,
                            icon: const Icon(Icons.sync_alt),
                            label: const Text('Quick swap'),
                          ),
                        const SizedBox(width: 8),
                        Chip(
                          padding: tight ? EdgeInsets.zero : null,
                          visualDensity: tight ? VisualDensity.compact : null,
                          label: Text('Rotation $rotation'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: compact ? 6 : 14),
            Text(
              selectedPlayerId == null
                  ? 'Select an on-court player'
                  : 'Selected: ${_playerLabel(team, selectedPlayerId!)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SizedBox(height: compact ? 3 : 8),
            _SkillActionGrid(
              enabled: selectedPlayerId != null,
              onAdd: (skill, grade) => onAdd(skill, grade, team),
              compact: compact,
              denseDesktop: denseSkillButtons,
            ),
            SizedBox(height: compact ? 4 : 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 720;
                if (narrow) {
                  final compactFilledStyle = FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                  final compactOutlinedStyle = OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  );
                  return Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () => onAdd(
                            Skill.opponentError,
                            ActionGrade.success,
                            team,
                          ),
                          style: compactFilledStyle,
                          child: const Text('OPP ERR  •  OP+'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              onAdd(Skill.teamFault, ActionGrade.error, team),
                          style: compactOutlinedStyle,
                          child: const Text('TEAM FAULT  •  T-'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FilledButton(
                          onPressed: onEnter,
                          style: compactFilledStyle,
                          child: const Text('Enter'),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          onAdd(Skill.opponentError, ActionGrade.success, team),
                      style: tonalStyle,
                      icon: Icon(
                        Icons.add_circle_outline,
                        size: compact ? 17 : 24,
                      ),
                      label: const Text('OPP ERR  •  OP+'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          onAdd(Skill.teamFault, ActionGrade.error, team),
                      style: outlinedStyle,
                      icon: Icon(
                        Icons.remove_circle_outline,
                        size: compact ? 17 : 24,
                      ),
                      label: const Text('TEAM FAULT  •  T-'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: onEnter,
                      style: tonalStyle,
                      icon: Icon(
                        Icons.keyboard_return,
                        size: compact ? 17 : 24,
                      ),
                      label: const Text('Enter'),
                    ),
                  ],
                );
              },
            ),
            if (pending.isNotEmpty) ...[
              SizedBox(height: compact ? 4 : 14),
              Text(
                'This rally',
                style: compact
                    ? Theme.of(context).textTheme.labelLarge
                    : Theme.of(context).textTheme.titleSmall,
              ),
              Wrap(
                spacing: 6,
                children: pending
                    .map(
                      (action) => InputChip(
                        visualDensity: compact ? VisualDensity.compact : null,
                        materialTapTargetSize: compact
                            ? MaterialTapTargetSize.shrinkWrap
                            : null,
                        label: Text(action.notation(team)),
                        onDeleted: () => onRemove(action),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _playerLabel(TournamentTeam team, String playerId) {
    final player = team.players
        .where((item) => item.id == playerId)
        .firstOrNull;
    return player == null
        ? 'Unknown player'
        : '#${player.number} ${player.name}';
  }
}

class _SkillActionGrid extends StatelessWidget {
  const _SkillActionGrid({
    required this.enabled,
    required this.onAdd,
    required this.compact,
    required this.denseDesktop,
  });

  final bool enabled;
  final void Function(Skill skill, ActionGrade grade) onAdd;
  final bool compact;
  final bool denseDesktop;

  static const skills = [
    (label: 'SERVICE', code: 'V', skill: Skill.serve),
    (label: 'ATTACK', code: 'A', skill: Skill.attack),
    (label: 'BLOCK', code: 'B', skill: Skill.block),
    (label: 'SET', code: 'S', skill: Skill.set),
    (label: 'RECEPTION', code: 'R', skill: Skill.reception),
    (label: 'DIG', code: 'D', skill: Skill.dig),
  ];

  @override
  Widget build(BuildContext context) {
    final dense = compact || denseDesktop;
    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: Size(0, dense ? 34 : 48),
      padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 12),
      visualDensity: dense ? VisualDensity.compact : null,
      tapTargetSize: denseDesktop ? MaterialTapTargetSize.shrinkWrap : null,
    );
    final successStyle = FilledButton.styleFrom(
      minimumSize: Size(0, dense ? 34 : 48),
      padding: EdgeInsets.symmetric(horizontal: dense ? 4 : 12),
      visualDensity: dense ? VisualDensity.compact : null,
      tapTargetSize: denseDesktop ? MaterialTapTargetSize.shrinkWrap : null,
    );
    return Column(
      children: [
        for (final item in skills)
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 3 : 7),
            child: Row(
              children: [
                SizedBox(
                  width: compact ? 82 : 112,
                  child: Text(
                    '${item.label} (${item.code})',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: compact ? 11 : null,
                    ),
                  ),
                ),
                Expanded(
                  child: OutlinedButton(
                    style: outlinedStyle,
                    onPressed: enabled
                        ? () => onAdd(item.skill, ActionGrade.attempt)
                        : null,
                    child: const Text('ATT'),
                  ),
                ),
                SizedBox(width: compact ? 3 : 6),
                Expanded(
                  child: FilledButton.tonal(
                    style: successStyle,
                    onPressed: enabled
                        ? () => onAdd(item.skill, ActionGrade.success)
                        : null,
                    child: const Text('EXC'),
                  ),
                ),
                SizedBox(width: compact ? 3 : 6),
                Expanded(
                  child: OutlinedButton(
                    style: outlinedStyle.copyWith(
                      foregroundColor: WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onPressed: enabled
                        ? () => onAdd(item.skill, ActionGrade.error)
                        : null,
                    child: const Text('ERR'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HalfCourt extends StatelessWidget {
  const _HalfCourt({
    required this.team,
    required this.playerIdsByPosition,
    required this.selectedPlayerId,
    required this.onSelected,
    this.positionKeyPrefix,
    this.onPositionMenuRequested,
    this.compact = false,
  });

  final TournamentTeam team;
  final List<String> playerIdsByPosition;
  final String? selectedPlayerId;
  final ValueChanged<String?> onSelected;
  final String? positionKeyPrefix;
  final void Function(int position, Offset globalPosition)?
  onPositionMenuRequested;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (playerIdsByPosition.length != 6) {
      return Container(
        constraints: BoxConstraints(minHeight: compact ? 130 : 180),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Complete the R-5 lineup to place six players on court.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Color(team.colorValue).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Color(team.colorValue).withValues(alpha: .5)),
      ),
      child: Column(
        children: [
          Container(
            height: compact ? 5 : 8,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(8, compact ? 2 : 6, 8, 2),
            child: Text(
              'NET • FRONT ROW',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          _courtRow(context, const [4, 3, 2]),
          Divider(height: compact ? 5 : 10, indent: 8, endIndent: 8),
          _courtRow(context, const [5, 6, 1]),
          SizedBox(height: compact ? 3 : 8),
        ],
      ),
    );
  }

  Widget _courtRow(BuildContext context, List<int> positions) => Row(
    children: [
      for (final position in positions)
        Expanded(child: _playerButton(context, position)),
    ],
  );

  Widget _playerButton(BuildContext context, int position) {
    final playerId = playerIdsByPosition[position - 1];
    final player = team.players.firstWhere((item) => item.id == playerId);
    final selected = playerId == selectedPlayerId;
    Offset? tapPosition;
    return Padding(
      padding: EdgeInsets.all(compact ? 3 : 5),
      child: Semantics(
        button: true,
        selected: selected,
        label:
            'Position ${_romanPosition(position)}, number ${player.number}, ${player.name}, ${player.position.name}',
        child: InkWell(
          key: positionKeyPrefix == null
              ? null
              : ValueKey('$positionKeyPrefix-$position'),
          onTapDown: onPositionMenuRequested == null
              ? null
              : (details) => tapPosition = details.globalPosition,
          onTap: () {
            final menuRequested = onPositionMenuRequested;
            if (menuRequested == null) {
              onSelected(playerId);
            } else {
              menuRequested(position, tapPosition ?? Offset.zero);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: BoxConstraints(minHeight: compact ? 52 : 74),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '#${player.number}',
                  style:
                      (compact
                              ? Theme.of(context).textTheme.titleMedium
                              : Theme.of(context).textTheme.titleLarge)
                          ?.copyWith(fontWeight: FontWeight.w900),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: compact ? 10 : 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${player.position.name} • ${_romanPosition(position)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: compact ? 9 : 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.log,
    required this.home,
    required this.away,
    required this.trackedTeam,
  });
  final ScorerLog log;
  final TournamentTeam home;
  final TournamentTeam away;
  final TournamentTeam trackedTeam;

  @override
  Widget build(BuildContext context) {
    final events = <_TimelineEvent>[
      for (final rally in log.rallies) _TimelineEvent.rally(rally),
      for (final substitution in log.substitutions)
        _TimelineEvent.substitution(substitution),
      for (final timeout in log.timeouts) _TimelineEvent.timeout(timeout),
    ]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Text(
            'Event timeline',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? const Center(child: Text('The first event will appear here.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: events.length,
                  itemBuilder: (context, index) => _eventTile(events[index]),
                ),
        ),
      ],
    );
  }

  Widget _eventTile(_TimelineEvent event) {
    final rally = event.rally;
    if (rally != null) {
      final winner = rally.winnerTeamId == home.id ? home : away;
      return ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 17,
          child: Text(
            '${rally.sequence}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        title: Text(
          '${winner.shortCode} point  •  ${rally.homeScore}-${rally.awayScore}',
        ),
        subtitle: Text(
          'Set ${rally.setNumber}${rally.actions.isEmpty ? '' : ' • ${rally.actions.map((action) => action.notation(trackedTeam)).join('  ')}'}',
        ),
      );
    }
    final substitution = event.substitution;
    if (substitution != null) {
      final outgoing = trackedTeam.players.firstWhere(
        (player) => player.id == substitution.playerOutId,
      );
      final incoming = trackedTeam.players.firstWhere(
        (player) => player.id == substitution.playerInId,
      );
      final liberoIncoming = incoming.isLibero;
      return ListTile(
        dense: true,
        leading: CircleAvatar(
          child: Icon(
            substitution.isLiberoReplacement
                ? Icons.sync_alt
                : Icons.swap_horiz,
            size: 18,
          ),
        ),
        title: Text(
          substitution.isLiberoReplacement
              ? liberoIncoming
                    ? 'Libero #${incoming.number} in • #${outgoing.number} out'
                    : '#${incoming.number} returns • Libero #${outgoing.number} out'
              : '#${incoming.number} in • #${outgoing.number} out',
        ),
        subtitle: Text(
          '${substitution.isLiberoReplacement ? 'Libero replacement • ' : ''}Set ${substitution.setNumber} • ${substitution.homeScore}-${substitution.awayScore}',
        ),
      );
    }
    final timeout = event.timeout!;
    return ListTile(
      dense: true,
      leading: const CircleAvatar(child: Icon(Icons.timer_outlined, size: 18)),
      title: Text('${trackedTeam.shortCode} timeout'),
      subtitle: Text(
        'Set ${timeout.setNumber} • ${timeout.homeScore}-${timeout.awayScore} • ${DateFormat.jm().format(timeout.recordedAt.toLocal())}',
      ),
    );
  }
}

class _R5LineupEditor extends StatelessWidget {
  const _R5LineupEditor({
    required this.team,
    required this.selectedPlayerIds,
    required this.onPlayerSelected,
  });

  final TournamentTeam team;
  final List<String> selectedPlayerIds;
  final void Function(int position, String playerId) onPlayerSelected;

  @override
  Widget build(BuildContext context) => _HalfCourt(
    team: team,
    playerIdsByPosition: selectedPlayerIds,
    selectedPlayerId: null,
    positionKeyPrefix: 'lineup-position',
    onSelected: (_) {},
    onPositionMenuRequested: (position, anchor) {
      _showPlayerDropdown(context, position, anchor);
    },
  );

  Future<void> _showPlayerDropdown(
    BuildContext context,
    int position,
    Offset anchor,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selectedPlayerId = await showMenu<String>(
      context: context,
      initialValue: selectedPlayerIds[position - 1],
      position: RelativeRect.fromLTRB(
        anchor.dx,
        anchor.dy,
        overlay.size.width - anchor.dx,
        overlay.size.height - anchor.dy,
      ),
      items: [
        for (final player in team.players)
          PopupMenuItem<String>(
            key: ValueKey('lineup-player-${player.id}'),
            value: player.id,
            child: SizedBox(
              width: 230,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#${player.number} ${player.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${player.position.name} • ${_assignmentLabel(player.id)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    if (selectedPlayerId != null && context.mounted) {
      onPlayerSelected(position - 1, selectedPlayerId);
    }
  }

  String _assignmentLabel(String playerId) {
    final position = selectedPlayerIds.indexOf(playerId);
    return position < 0 ? 'Bench' : 'Position ${_romanPosition(position + 1)}';
  }
}

class _TimelineEvent {
  const _TimelineEvent._({
    required this.recordedAt,
    this.rally,
    this.substitution,
    this.timeout,
  });

  factory _TimelineEvent.rally(Rally rally) =>
      _TimelineEvent._(recordedAt: rally.recordedAt, rally: rally);
  factory _TimelineEvent.substitution(Substitution substitution) =>
      _TimelineEvent._(
        recordedAt: substitution.recordedAt,
        substitution: substitution,
      );
  factory _TimelineEvent.timeout(TeamTimeout timeout) =>
      _TimelineEvent._(recordedAt: timeout.recordedAt, timeout: timeout);

  final DateTime recordedAt;
  final Rally? rally;
  final Substitution? substitution;
  final TeamTimeout? timeout;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
