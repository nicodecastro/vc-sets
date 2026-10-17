import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/scoring.dart';

import 'test_fixtures.dart';

void main() {
  const engine = ScoringEngine();
  const rules = MatchRules();

  test('set requires target and two-point margin', () {
    expect(engine.isSetComplete(25, 24, 1, rules), isFalse);
    expect(engine.isSetComplete(26, 24, 1, rules), isTrue);
    expect(engine.isSetComplete(14, 16, 5, rules), isTrue);
  });

  test('a game can override the target of an individual set', () {
    const custom = MatchRules(setTargets: {2: 21, 5: 18});
    expect(custom.targetForSet(1), 25);
    expect(custom.targetForSet(2), 21);
    expect(custom.targetForSet(5), 18);
    expect(engine.isSetComplete(21, 19, 2, custom), isTrue);
    expect(engine.isSetComplete(20, 18, 2, custom), isFalse);
    expect(engine.isSetComplete(18, 16, 5, custom), isTrue);
    expect(MatchRules.fromJson(custom.toJson()).setTargets, {2: 21, 5: 18});
    expect(
      MatchRules.fromJson(const MatchRules().toJson()).setTargets,
      isEmpty,
    );
  });

  test('extra rallies after a completed set are identified', () {
    final log = testLog(
      rallies: [
        Rally(
          id: 'r1',
          setNumber: 1,
          sequence: 1,
          winnerTeamId: homeTeam.id,
          homeScore: 1,
          awayScore: 0,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: homeTeam.id,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
        Rally(
          id: 'r2',
          setNumber: 1,
          sequence: 2,
          winnerTeamId: homeTeam.id,
          homeScore: 2,
          awayScore: 0,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: homeTeam.id,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
      ],
    );
    expect(
      engine.excessRallyReason(
        log,
        const MatchRules(
          setsToWin: 1,
          maxSets: 1,
          regularSetTarget: 1,
          winBy: 1,
        ),
      ),
      contains('Remove the excess rally'),
    );
    expect(
      engine.excessRallyReason(
        testLog(
          rallies: [
            log.rallies.first,
            Rally(
              id: 'next-set',
              setNumber: 2,
              sequence: 1,
              winnerTeamId: awayTeam.id,
              homeScore: 0,
              awayScore: 1,
              homeRotation: 1,
              awayRotation: 1,
              servingTeamId: awayTeam.id,
              recordedAt: DateTime.utc(2026, 10, 2),
            ),
          ],
        ),
        const MatchRules(
          setsToWin: 1,
          maxSets: 1,
          regularSetTarget: 1,
          winBy: 1,
        ),
      ),
      contains('after the match was won'),
    );
  });

  test('removing a middle rally requires correcting later scores', () {
    final log = testLog(
      rallies: [
        Rally(
          id: 'r1',
          setNumber: 1,
          sequence: 1,
          winnerTeamId: homeTeam.id,
          homeScore: 1,
          awayScore: 0,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: homeTeam.id,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
        Rally(
          id: 'r3',
          setNumber: 1,
          sequence: 2,
          winnerTeamId: homeTeam.id,
          homeScore: 3,
          awayScore: 0,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: homeTeam.id,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
      ],
    );
    expect(
      engine.scoreProgressionReason(testGame(), log),
      contains('Manual override'),
    );
  });

  test('one-set matches use the regular target and finish after that set', () {
    const oneSetRules = MatchRules(setsToWin: 1, maxSets: 1);
    final game = testGame();
    var log = testLog();

    expect(engine.isSetComplete(15, 0, 1, oneSetRules), isFalse);
    for (var point = 0; point < 25; point++) {
      final rally = engine.nextRally(
        id: 'single-$point',
        game: game,
        log: log,
        rules: oneSetRules,
        winnerTeamId: homeTeam.id,
        recordedAt: DateTime.utc(2026, 10, 3),
      );
      log = log.copyWith(rallies: [...log.rallies, rally]);
    }

    final score = engine.score(game, log, oneSetRules);
    expect(score.homePoints, 25);
    expect(score.homeSets, 1);
    expect(score.awaySets, 0);
    expect(score.isComplete, isTrue);
  });

  test('incomplete match reason identifies sets and points still required', () {
    final game = testGame();
    final log = testLog(
      rallies: [
        engine.nextRally(
          id: 'r1',
          game: game,
          log: testLog(),
          rules: rules,
          winnerTeamId: homeTeam.id,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
      ],
    );

    expect(
      engine.incompleteMatchReason(game, log, rules),
      'The reconciled result is 0-0 in sets, but 3 set win(s) are required. '
      'Set 1 is 1-0; a team must reach 25 with a 2-point lead.',
    );
  });

  test('sideout rotates receiving team and winner serves', () {
    final game = testGame();
    final empty = testLog();
    final first = engine.nextRally(
      id: 'r1',
      game: game,
      log: empty,
      rules: rules,
      winnerTeamId: awayTeam.id,
      recordedAt: DateTime.utc(2026, 10, 2),
    );
    expect(first.awayRotation, 2);
    expect(first.servingTeamId, awayTeam.id);

    final second = engine.nextRally(
      id: 'r2',
      game: game,
      log: empty.copyWith(rallies: [first]),
      rules: rules,
      winnerTeamId: awayTeam.id,
      recordedAt: DateTime.utc(2026, 10, 2),
    );
    expect(
      second.awayRotation,
      2,
      reason: 'Serving team does not rotate after holding serve',
    );
  });

  test('last decisive action infers the rally winner', () {
    final game = testGame();
    final now = DateTime.utc(2026, 10, 2);
    TeamAction action(Skill skill, ActionGrade grade) => TeamAction(
      id: '${skill.name}-${grade.name}',
      teamId: homeTeam.id,
      playerId: homeTeam.players.first.id,
      skill: skill,
      grade: grade,
      recordedAt: now,
    );

    for (final skill in [
      Skill.serve,
      Skill.attack,
      Skill.block,
      Skill.opponentError,
    ]) {
      expect(
        engine.inferRallyWinner(game, homeTeam.id, [
          action(skill, ActionGrade.success),
        ]),
        homeTeam.id,
      );
    }
    for (final skill in Skill.values) {
      expect(
        engine.inferRallyWinner(game, homeTeam.id, [
          action(skill, ActionGrade.error),
        ]),
        awayTeam.id,
      );
    }
    expect(
      engine.inferRallyWinner(game, homeTeam.id, [
        action(Skill.dig, ActionGrade.success),
      ]),
      isNull,
    );
    expect(engine.inferRallyWinner(game, homeTeam.id, const []), isNull);
  });

  test('three completed sets complete a match and preserve set count', () {
    final game = testGame();
    var log = testLog();
    var id = 0;
    for (var set = 0; set < 3; set++) {
      for (var point = 0; point < 25; point++) {
        final rally = engine.nextRally(
          id: 'r${id++}',
          game: game,
          log: log,
          rules: rules,
          winnerTeamId: homeTeam.id,
          recordedAt: DateTime.utc(2026, 10, 2),
        );
        log = log.copyWith(rallies: [...log.rallies, rally]);
      }
    }
    final score = engine.score(game, log, rules);
    expect(score.homeSets, 3);
    expect(score.awaySets, 0);
    expect(score.isComplete, isTrue);
    expect(
      () => engine.nextRally(
        id: 'extra',
        game: game,
        log: log,
        rules: rules,
        winnerTeamId: homeTeam.id,
        recordedAt: DateTime.now(),
      ),
      throwsStateError,
    );
  });

  test('starting lineup validation catches count and duplicates', () {
    expect(
      engine.validateStartingLineup(
        homeTeam,
        homeTeam.players.map((p) => p.id).toList(),
      ),
      isEmpty,
    );
    expect(
      engine.validateStartingLineup(homeTeam, ['home-0', 'home-0']),
      hasLength(greaterThanOrEqualTo(2)),
    );
  });

  test('skill actions use the requested compact rally notation', () {
    final now = DateTime.utc(2026, 10, 2);
    String notation(Skill skill, ActionGrade grade, {bool player = true}) =>
        TeamAction(
          id: '${skill.name}-${grade.name}',
          teamId: homeTeam.id,
          playerId: player ? homeTeam.players.first.id : null,
          skill: skill,
          grade: grade,
          recordedAt: now,
        ).notation(homeTeam);

    expect(notation(Skill.serve, ActionGrade.attempt), 'V1');
    expect(notation(Skill.serve, ActionGrade.success), 'V1+');
    expect(notation(Skill.serve, ActionGrade.error), 'V1-');
    expect(notation(Skill.attack, ActionGrade.attempt), 'A1');
    expect(notation(Skill.block, ActionGrade.error), 'B1-');
    expect(notation(Skill.set, ActionGrade.success), 'S1+');
    expect(notation(Skill.reception, ActionGrade.attempt), 'R1');
    expect(notation(Skill.dig, ActionGrade.success), 'D1+');
    expect(
      notation(Skill.opponentError, ActionGrade.success, player: false),
      'OP+',
    );
    expect(notation(Skill.teamFault, ActionGrade.error, player: false), 'T-');
  });

  test('EXC and ERR grade the immediately preceding matching ATT', () {
    const composer = RallyActionComposer();
    final attemptedAt = DateTime.utc(2026, 10, 2, 9);
    final attempt = TeamAction(
      id: 'attempt-id',
      teamId: homeTeam.id,
      playerId: homeTeam.players.first.id,
      skill: Skill.serve,
      grade: ActionGrade.attempt,
      recordedAt: attemptedAt,
    );
    final excellent = TeamAction(
      id: 'unused-excellent-id',
      teamId: homeTeam.id,
      playerId: homeTeam.players.first.id,
      skill: Skill.serve,
      grade: ActionGrade.success,
      recordedAt: attemptedAt.add(const Duration(seconds: 1)),
    );

    final upgraded = composer.add([attempt], excellent);

    expect(upgraded, hasLength(1));
    expect(upgraded.single.id, 'attempt-id');
    expect(upgraded.single.recordedAt, attemptedAt);
    expect(upgraded.single.grade, ActionGrade.success);
    expect(upgraded.single.notation(homeTeam), 'V1+');

    final error = excellent.copyWith(grade: ActionGrade.error);
    final downgraded = composer.add([attempt], error);
    expect(downgraded, hasLength(1));
    expect(downgraded.single.id, 'attempt-id');
    expect(downgraded.single.notation(homeTeam), 'V1-');
  });

  test('direct grades and nonmatching grades remain separate actions', () {
    const composer = RallyActionComposer();
    final now = DateTime.utc(2026, 10, 2, 9);
    TeamAction action(
      String id,
      Skill skill,
      ActionGrade grade, {
      String? playerId,
    }) => TeamAction(
      id: id,
      teamId: homeTeam.id,
      playerId: playerId ?? homeTeam.players.first.id,
      skill: skill,
      grade: grade,
      recordedAt: now,
    );

    final direct = composer.add(
      const [],
      action('direct', Skill.attack, ActionGrade.success),
    );
    expect(direct, hasLength(1));
    expect(direct.single.notation(homeTeam), 'A1+');

    final attempt = action('attempt', Skill.serve, ActionGrade.attempt);
    final otherSkill = action('dig', Skill.dig, ActionGrade.success);
    final separate = composer.add([attempt], otherSkill);
    expect(separate, hasLength(2));
    expect(
      separate.map((item) => item.notation(homeTeam)),
      orderedEquals(['V1', 'D1+']),
    );
  });
}
