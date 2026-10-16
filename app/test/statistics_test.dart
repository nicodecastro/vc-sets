import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/application/file_exchange.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/scoring.dart';
import 'package:vc_sets/domain/statistics.dart';

import 'test_fixtures.dart';

void main() {
  test('game stats use only the official log and honor the set filter', () {
    final now = DateTime.utc(2026, 10, 2);
    final home = homeTeam.copyWith(players: homeTeam.players.reversed.toList());
    TeamAction action(
      String id,
      String teamId,
      String? playerId,
      Skill skill,
      ActionGrade grade,
    ) => TeamAction(
      id: id,
      teamId: teamId,
      playerId: playerId,
      skill: skill,
      grade: grade,
      recordedAt: now,
    );
    final official =
        testLog(
          id: 'official',
          rallies: [
            Rally(
              id: 'set-one',
              setNumber: 1,
              sequence: 1,
              winnerTeamId: home.id,
              homeScore: 1,
              awayScore: 0,
              homeRotation: 1,
              awayRotation: 1,
              servingTeamId: home.id,
              recordedAt: now,
              actions: [
                action(
                  'serve',
                  home.id,
                  homeTeam.players.first.id,
                  Skill.serve,
                  ActionGrade.success,
                ),
                action(
                  'op',
                  home.id,
                  null,
                  Skill.opponentError,
                  ActionGrade.success,
                ),
              ],
            ),
            Rally(
              id: 'set-two',
              setNumber: 2,
              sequence: 1,
              winnerTeamId: awayTeam.id,
              homeScore: 0,
              awayScore: 1,
              homeRotation: 1,
              awayRotation: 1,
              servingTeamId: awayTeam.id,
              recordedAt: now,
              actions: [
                action(
                  'attack',
                  home.id,
                  homeTeam.players.first.id,
                  Skill.attack,
                  ActionGrade.error,
                ),
                action(
                  'fault',
                  home.id,
                  null,
                  Skill.teamFault,
                  ActionGrade.error,
                ),
              ],
            ),
          ],
        ).copyWith(
          lineups: [
            for (final setNumber in [1, 2])
              LineupSnapshot(
                teamId: home.id,
                playerIds: homeTeam.players.map((player) => player.id).toList(),
                setNumber: setNumber,
              ),
          ],
        );
    final game = testGame(officialLog: official);
    const stats = StatisticsService();
    final all = stats.gamePlayerStats(game, home);
    expect(all.first.player.number, 1);
    expect(all.first.setsPlayed, 2);
    expect(all.first.counts['V+'], 1);
    expect(all.first.counts['A-'], 1);
    expect(all.first.points, 1);
    expect(all.first.counts['OP+'], isNull);
    expect(all[1].setsPlayed, 2);
    expect(all[1].counts, isEmpty);

    final setTwo = stats.gamePlayerStats(game, home, setNumber: 2);
    expect(setTwo.first.setsPlayed, 1);
    expect(setTwo.first.counts['V+'], isNull);
    expect(setTwo.first.counts['A-'], 1);
    expect(setTwo.first.points, 0);
    expect(stats.gameTeamActionCount(game, home.id, Skill.opponentError), 1);
    expect(stats.gameTeamSkillCounts(game, home.id)['V+'], 1);
    expect(stats.gameTeamSkillCounts(game, home.id)['A-'], 1);
    expect(
      stats.gameTeamSkillCounts(game, home.id, setNumber: 2)['V+'],
      isNull,
    );
    expect(
      stats.gameTeamActionCount(game, home.id, Skill.teamFault, setNumber: 2),
      1,
    );
    expect(
      stats.gameTeamActionCount(
        game,
        home.id,
        Skill.opponentError,
        setNumber: 2,
      ),
      0,
    );
    expect(stats.gamePlayerStats(testGame(logs: [official]), home), isEmpty);
  });

  test('player points include only excellent serves, attacks, and blocks', () {
    final row = GamePlayerStatRow(
      player: homeTeam.players.first,
      setsPlayed: 1,
      counts: const {
        'V+': 2,
        'A+': 3,
        'B+': 4,
        'S+': 5,
        'R+': 6,
        'D+': 7,
        'V-': 8,
        'A': 9,
      },
    );
    expect(row.points, 9);
  });

  test('finalized match drives standings and player totals', () {
    const engine = ScoringEngine();
    var log = testLog();
    final game = testGame();
    var id = 0;
    for (var set = 0; set < 3; set++) {
      for (var point = 0; point < 25; point++) {
        final actions = id == 0
            ? [
                TeamAction(
                  id: 'action',
                  teamId: homeTeam.id,
                  playerId: homeTeam.players.first.id,
                  skill: Skill.attack,
                  grade: ActionGrade.success,
                  recordedAt: DateTime.utc(2026, 10, 2),
                ),
              ]
            : const <TeamAction>[];
        final rally = engine.nextRally(
          id: 'r${id++}',
          game: game,
          log: log,
          rules: const MatchRules(),
          winnerTeamId: homeTeam.id,
          recordedAt: DateTime.utc(2026, 10, 2),
          actions: actions,
        );
        log = log.copyWith(rallies: [...log.rallies, rally]);
      }
    }
    final finalized = testGame(officialLog: log);
    final tournament = testTournament(games: [finalized]);
    final standings = const StatisticsService().standings(tournament);
    expect(standings.first.team.id, homeTeam.id);
    expect(standings.first.matchPoints, 3);
    expect(standings.first.setsWon, 3);
    expect(standings.first.pointsWon, 75);
    final players = const StatisticsService().playerSummaries(tournament);
    expect(players.single.bySkill[Skill.attack]?.successes, 1);
  });

  test('bracket games do not change round-robin standings', () {
    ScorerLog sweep(String id, String winner) => ScorerLog(
      id: 'log-$id',
      gameId: id,
      assignedTeamId: 'official',
      deviceId: 'device',
      createdAt: DateTime.utc(2026, 10, 2),
      updatedAt: DateTime.utc(2026, 10, 2),
      initialServingTeamId: homeTeam.id,
      rallies: [
        for (var set = 1; set <= 3; set++)
          Rally(
            id: '$id-$set',
            setNumber: set,
            sequence: 1,
            winnerTeamId: winner,
            homeScore: winner == homeTeam.id ? 25 : 0,
            awayScore: winner == awayTeam.id ? 25 : 0,
            homeRotation: 1,
            awayRotation: 1,
            servingTeamId: winner,
            recordedAt: DateTime.utc(2026, 10, 2),
          ),
      ],
    );

    final poolLog = sweep('pool', homeTeam.id);
    final bracketLog = sweep('final', awayTeam.id);
    final pool = Game(
      id: 'pool',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: DateTime.utc(2026, 10, 2),
      venue: 'Gym',
      status: GameStatus.finalized,
      officialLog: poolLog,
    );
    final finalGame = Game(
      id: 'final',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: DateTime.utc(2026, 10, 3),
      venue: 'Gym',
      stage: GameStage.bracket,
      bracketRound: 1,
      bracketOrder: 0,
      status: GameStatus.finalized,
      officialLog: bracketLog,
    );
    final standings = const StatisticsService().standings(
      testTournament(games: [pool, finalGame]),
    );
    expect(standings.first.team.id, homeTeam.id);
    expect(standings.first.wins, 1);
    expect(standings.last.wins, 0);
  });

  test('one-set matches award clear-win standings points', () {
    const oneSetRules = MatchRules(setsToWin: 1, maxSets: 1);
    final now = DateTime.utc(2026, 10, 3);
    final official = ScorerLog(
      id: 'one-set-log',
      gameId: 'one-set-game',
      assignedTeamId: 'official',
      deviceId: 'device',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: homeTeam.id,
      rallies: [
        Rally(
          id: 'one-set-rally',
          setNumber: 1,
          sequence: 25,
          winnerTeamId: homeTeam.id,
          homeScore: 25,
          awayScore: 10,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: homeTeam.id,
          recordedAt: now,
        ),
      ],
    );
    final game = Game(
      id: 'one-set-game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: now,
      venue: 'Gym',
      status: GameStatus.finalized,
      rulesSnapshot: oneSetRules,
      officialLog: official,
    );

    final standings = const StatisticsService().standings(
      testTournament(games: [game]).copyWith(poolRules: oneSetRules),
    );

    expect(standings.first.team.id, homeTeam.id);
    expect(standings.first.matchPoints, 3);
    expect(standings.last.matchPoints, 0);
  });

  test('player stats matrix buckets notation and repeats team faults', () {
    const first = Player(
      id: 'p1',
      number: 2,
      name: 'De la Cruz, Ana Marie',
      position: PlayerPosition.S,
    );
    const second = Player(
      id: 'p2',
      number: 11,
      name: 'Bea Cruz',
      position: PlayerPosition.OH,
    );
    final team = homeTeam.copyWith(players: [first, second]);
    final now = DateTime.utc(2026, 10, 2);
    TeamAction action(
      String id,
      Skill skill,
      ActionGrade grade, {
      String? playerId = 'p1',
    }) => TeamAction(
      id: id,
      teamId: team.id,
      playerId: playerId,
      skill: skill,
      grade: grade,
      recordedAt: now,
    );
    final log = ScorerLog(
      id: 'official',
      gameId: 'game',
      assignedTeamId: 'official',
      deviceId: 'device',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: team.id,
      lineups: [
        LineupSnapshot(teamId: team.id, playerIds: [first.id], setNumber: 1),
      ],
      rallies: [
        Rally(
          id: 'rally',
          setNumber: 1,
          sequence: 1,
          winnerTeamId: team.id,
          homeScore: 25,
          awayScore: 0,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: team.id,
          recordedAt: now,
          actions: [
            action('set-att', Skill.set, ActionGrade.attempt),
            action('set-exc', Skill.set, ActionGrade.success),
            action('serve-err', Skill.serve, ActionGrade.error),
            action('dig-exc', Skill.dig, ActionGrade.positive),
            action(
              'op-1',
              Skill.opponentError,
              ActionGrade.success,
              playerId: null,
            ),
            action(
              'op-2',
              Skill.opponentError,
              ActionGrade.success,
              playerId: null,
            ),
            action('fault', Skill.teamFault, ActionGrade.error, playerId: null),
          ],
        ),
        Rally(
          id: 'set-two-rally',
          setNumber: 2,
          sequence: 1,
          winnerTeamId: team.id,
          homeScore: 25,
          awayScore: 0,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: team.id,
          recordedAt: now,
        ),
      ],
    );
    final game = Game(
      id: 'game',
      tournamentId: 'tournament',
      homeTeamId: team.id,
      awayTeamId: awayTeam.id,
      scheduledAt: now,
      venue: 'Gym',
      status: GameStatus.finalized,
      rulesSnapshot: const MatchRules(setsToWin: 2, maxSets: 3),
      officialLog: log,
    );
    final tournament = testTournament(games: [game])
        .copyWith(teams: [team, awayTeam]);

    final rows = const StatisticsService().playerStatsSummary(tournament);
    final ana = rows.firstWhere((row) => row.player.id == first.id);
    final bea = rows.firstWhere((row) => row.player.id == second.id);
    expect(playerStatColumns, [
      'S',
      'S+',
      'S-',
      'V',
      'V+',
      'V-',
      'D',
      'D+',
      'D-',
      'R',
      'R+',
      'R-',
      'A',
      'A+',
      'A-',
      'B',
      'B+',
      'B-',
      'OP+',
      'T-',
    ]);
    expect(ana.lastName, 'De la Cruz');
    expect(ana.counts['S'], 1);
    expect(ana.counts['S+'], 1);
    expect(ana.counts['V-'], 1);
    expect(ana.counts['D+'], 1);
    expect(ana.counts['OP+'], 2);
    expect(ana.counts['T-'], 1);
    expect(ana.gamesPlayed, 1);
    expect(ana.setsPlayed, 1);
    expect(ana.gamesWon, 1);
    expect(bea.lastName, 'Cruz');
    expect(bea.counts['S'], 0);
    expect(bea.counts['OP+'], 2);
    expect(bea.counts['T-'], 1);
    expect(bea.gamesPlayed, 0);
    expect(bea.setsPlayed, 0);
    expect(bea.gamesWon, 0);
    final csv = const FileExchangeService().playerStatsCsv(tournament);
    expect(
      csv.split('\r\n').first,
      'Team,Last name,Number,${playerStatColumns.join(',')},Games played,Sets played,Games won',
    );
    expect(csv, contains('"${team.name}","De la Cruz",2,'));
    expect(csv, contains(',1,1,1'));
  });
}
