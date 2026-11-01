import 'dart:math';

import 'models.dart';
import 'scoring.dart';

const sampleTournamentId = 'vc-sets-fictional-sample-v1';

Tournament buildSampleTournament() {
  final start = DateTime.utc(2026, 10, 20, 9);
  const rules = MatchRules(
    setsToWin: 2,
    maxSets: 3,
    regularSetTarget: 25,
    decidingSetTarget: 15,
    winBy: 2,
  );
  const names = [
    ('Harbor Spikers', 'HBR', 0xFF156B8A),
    ('Summit Six', 'SMT', 0xFFAD513A),
    ('Cedar Volley', 'CDR', 0xFF39785E),
    ('Metro Aces', 'MTR', 0xFF76559B),
  ];
  const positions = [
    PlayerPosition.S,
    PlayerPosition.OH,
    PlayerPosition.OH,
    PlayerPosition.OPP,
    PlayerPosition.MB,
    PlayerPosition.MB,
    PlayerPosition.L,
  ];
  final teams = [
    for (var t = 0; t < names.length; t++)
      TournamentTeam(
        id: 'sample-team-$t',
        name: names[t].$1,
        shortCode: names[t].$2,
        colorValue: names[t].$3,
        players: [
          for (var p = 0; p < positions.length; p++)
            Player(
              id: 'sample-player-$t-$p',
              number: p + 1,
              name:
                  '${['Alex', 'Riley', 'Jordan', 'Casey', 'Morgan', 'Taylor', 'Sam'][p]} ${['Bay', 'Peak', 'Grove', 'Vale'][t]}',
              position: positions[p],
              isCaptain: p == 0,
            ),
        ],
      ),
  ];
  final pairings = [(0, 1), (2, 3), (0, 2), (1, 3), (0, 3), (1, 2)];
  final games = [
    for (var i = 0; i < pairings.length; i++)
      _sampleGame(
        i,
        teams[pairings[i].$1],
        teams[pairings[i].$2],
        start.add(Duration(hours: i * 2)),
        rules,
      ),
  ];
  return Tournament(
    id: sampleTournamentId,
    name: 'Sample Invitational (Fictional)',
    venue: 'Demo Sports Hall',
    startsOn: start,
    endsOn: start.add(const Duration(days: 2)),
    createdAt: start,
    status: TournamentStatus.active,
    rules: rules,
    teams: teams,
    games: games,
  );
}

Game _sampleGame(
  int index,
  TournamentTeam home,
  TournamentTeam away,
  DateTime scheduledAt,
  MatchRules rules,
) {
  final id = 'sample-game-$index';
  var game = Game(
    id: id,
    tournamentId: sampleTournamentId,
    homeTeamId: home.id,
    awayTeamId: away.id,
    scheduledAt: scheduledAt,
    venue: 'Demo Sports Hall',
    stage: GameStage.pool,
    poolNumber: 1,
    rulesSnapshot: rules,
  );
  if (index >= 5) return game;

  final setScores = switch (index) {
    0 => [(25, 19), (22, 25), (15, 12)],
    1 => [(25, 21), (25, 20)],
    _ => [(23, 25), (25, 22), (13, 15)],
  };
  final lineups = [
    for (var set = 1; set <= setScores.length; set++)
      for (final team in [home, away])
        LineupSnapshot(
          teamId: team.id,
          playerIds: team.players.take(6).map((player) => player.id).toList(),
          setNumber: set,
          recordedAt: scheduledAt,
        ),
  ];
  var official = ScorerLog(
    id: '$id-official',
    gameId: id,
    assignedTeamId: home.id,
    deviceId: 'sample-official',
    createdAt: scheduledAt,
    updatedAt: scheduledAt,
    initialServingTeamId: home.id,
    lineups: lineups,
  );
  const engine = ScoringEngine();
  final random = Random(index + 2026);
  var actionIndex = 0;
  for (final (homeTarget, awayTarget) in setScores) {
    final winners = <String>[];
    var h = 0;
    var a = 0;
    final homeBeforeLast = homeTarget > awayTarget
        ? homeTarget - 1
        : homeTarget;
    final awayBeforeLast = awayTarget > homeTarget
        ? awayTarget - 1
        : awayTarget;
    while (h < homeBeforeLast || a < awayBeforeLast) {
      if (h < homeBeforeLast && (h <= a || a == awayBeforeLast)) {
        winners.add(home.id);
        h++;
      } else if (a < awayBeforeLast) {
        winners.add(away.id);
        a++;
      }
    }
    winners.add(homeTarget > awayTarget ? home.id : away.id);
    for (final winner in winners) {
      final winningTeam = winner == home.id ? home : away;
      final losingTeam = winner == home.id ? away : home;
      final at = scheduledAt.add(Duration(seconds: actionIndex * 35));
      final actions = <TeamAction>[];
      void add(
        TournamentTeam team,
        int player,
        Skill skill,
        ActionGrade grade,
      ) {
        actions.add(
          TeamAction(
            id: '$id-action-$actionIndex-${actions.length}',
            teamId: team.id,
            playerId: team.players[player].id,
            skill: skill,
            grade: grade,
            recordedAt: at,
          ),
        );
      }

      // A rally can have several touches, but only its last scoring action awards the point.
      final pattern = actionIndex % 10;
      final serverId = engine.score(game, official, rules).servingTeamId;
      final servingTeam = serverId == home.id ? home : away;
      final receivingTeam = serverId == home.id ? away : home;
      if (pattern != 0 || serverId != winner) {
        add(servingTeam, random.nextInt(6), Skill.serve, ActionGrade.neutral);
        add(
          receivingTeam,
          random.nextBool() ? 6 : random.nextInt(6),
          Skill.reception,
          receivingTeam.id == winner
              ? ActionGrade.positive
              : ActionGrade.neutral,
        );
        if (pattern.isEven) {
          add(
            losingTeam,
            random.nextBool() ? 6 : random.nextInt(6),
            Skill.dig,
            ActionGrade.positive,
          );
        }
        add(
          winningTeam,
          0,
          Skill.set,
          random.nextInt(5) == 0 ? ActionGrade.neutral : ActionGrade.positive,
        );
      }
      switch (pattern) {
        case 0:
          add(
            winningTeam,
            random.nextInt(6),
            serverId == winner ? Skill.serve : Skill.attack,
            ActionGrade.success,
          );
        case 1:
        case 6:
          add(
            losingTeam,
            random.nextInt(6),
            receivingTeam.id == losingTeam.id ? Skill.reception : Skill.attack,
            ActionGrade.error,
          );
          add(
            winningTeam,
            random.nextInt(6),
            Skill.opponentError,
            ActionGrade.success,
          );
        case 2:
        case 7:
          add(
            winningTeam,
            4 + random.nextInt(2),
            Skill.block,
            ActionGrade.success,
          );
        case 3:
          add(losingTeam, random.nextInt(6), Skill.attack, ActionGrade.error);
          add(losingTeam, random.nextInt(6), Skill.error, ActionGrade.error);
        case 4:
          add(
            losingTeam,
            random.nextInt(6),
            Skill.teamFault,
            ActionGrade.error,
          );
        default:
          add(
            losingTeam,
            random.nextBool() ? 6 : random.nextInt(6),
            Skill.dig,
            random.nextInt(4) == 0 ? ActionGrade.error : ActionGrade.neutral,
          );
          add(
            winningTeam,
            1 + random.nextInt(3),
            Skill.attack,
            ActionGrade.success,
          );
      }
      final rally = engine.nextRally(
        id: '$id-rally-$actionIndex',
        game: game,
        log: official,
        rules: rules,
        winnerTeamId: winner,
        recordedAt: at,
        actions: actions,
      );
      official = official.copyWith(rallies: [...official.rallies, rally]);
      actionIndex++;
    }
  }
  final logs = [
    for (final team in [home, away])
      ScorerLog(
        id: '$id-${team.id}-log',
        gameId: id,
        assignedTeamId: team.id,
        deviceId: 'sample-${team.id}',
        createdAt: scheduledAt,
        updatedAt: scheduledAt.add(Duration(seconds: actionIndex * 35)),
        initialServingTeamId: home.id,
        lineups: lineups,
        rallies: [
          for (final rally in official.rallies)
            // Keep alignment keys intact so each omitted rally is one conflict.
            if (!(index == 3 &&
                team.id == away.id &&
                rally.setNumber == 1 &&
                const [5, 10].contains(rally.sequence)))
              Rally(
                id: rally.id,
                setNumber: rally.setNumber,
                sequence: rally.sequence,
                winnerTeamId:
                    index == 3 &&
                        team.id == away.id &&
                        rally.setNumber == 1 &&
                        const [15, 20].contains(rally.sequence)
                    ? (rally.winnerTeamId == home.id ? away.id : home.id)
                    : rally.winnerTeamId,
                homeScore:
                    rally.homeScore +
                    (index == 3 &&
                            team.id == away.id &&
                            rally.setNumber == 1 &&
                            const [25, 30].contains(rally.sequence)
                        ? 1
                        : 0),
                awayScore: rally.awayScore,
                homeRotation: rally.homeRotation,
                awayRotation: rally.awayRotation,
                servingTeamId: rally.servingTeamId,
                recordedAt: rally.recordedAt,
                actions: rally.actions
                    .where((a) => a.teamId == team.id)
                    .toList(),
              ),
        ],
      ),
  ];
  if (index >= 3) {
    return game.copyWith(status: GameStatus.awaitingReconciliation, logs: logs);
  }
  game = game.copyWith(
    status: GameStatus.finalized,
    logs: logs,
    officialLog: official,
    revisions: [
      FinalizationRevision(
        id: '$id-finalization',
        finalizedAt: scheduledAt.add(Duration(seconds: actionIndex * 35)),
        reason: 'Fictional sample result',
        officialLog: official,
      ),
    ],
  );
  return game;
}
