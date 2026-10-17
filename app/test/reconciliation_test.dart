import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/application/providers.dart';
import 'package:vc_sets/data/repository.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/reconciliation.dart';

import 'test_fixtures.dart';

Rally rally(
  String id,
  int sequence,
  String winner,
  int home,
  int away, {
  int setNumber = 1,
  List<TeamAction> actions = const [],
}) => Rally(
  id: id,
  setNumber: setNumber,
  sequence: sequence,
  winnerTeamId: winner,
  homeScore: home,
  awayScore: away,
  homeRotation: 1,
  awayRotation: 1,
  servingTeamId: winner,
  recordedAt: DateTime.utc(2026, 10, 2),
  actions: actions,
);

void main() {
  const service = ReconciliationService();

  test('set-number swap moves whole sets before comparing and merging', () {
    final primary = testLog(
      rallies: [
        rally('first', 1, 'home', 1, 0),
        rally('second', 1, 'away', 0, 1, setNumber: 2),
      ],
    );
    final imported = ScorerLog(
      id: 'log-b',
      gameId: 'game',
      assignedTeamId: awayTeam.id,
      deviceId: 'device-b',
      createdAt: DateTime.utc(2026, 10, 2),
      updatedAt: DateTime.utc(2026, 10, 2),
      initialServingTeamId: awayTeam.id,
      rallies: [
        rally('wrong-first', 1, 'away', 0, 1),
        rally('wrong-second', 1, 'home', 1, 0, setNumber: 2),
      ],
      lineups: [
        LineupSnapshot(teamId: awayTeam.id, playerIds: const [], setNumber: 1),
      ],
      substitutions: [
        Substitution(
          id: 'sub',
          teamId: awayTeam.id,
          setNumber: 1,
          playerOutId: 'away-0',
          playerInId: 'away-1',
          homeScore: 0,
          awayScore: 1,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
      ],
      timeouts: [
        TeamTimeout(
          id: 'timeout',
          teamId: awayTeam.id,
          setNumber: 2,
          homeScore: 1,
          awayScore: 0,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
      ],
      rotationAdjustments: [
        RotationAdjustment(
          id: 'rotation',
          teamId: awayTeam.id,
          setNumber: 2,
          afterRallySequence: 1,
          rotation: 2,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
      ],
    );
    expect(service.compare(primary, imported).conflicts, hasLength(2));
    final corrected = service.remapSetNumbers(imported, const {1: 2, 2: 1});
    expect(corrected.rallies.map((item) => item.setNumber), [2, 1]);
    expect(corrected.lineups.single.setNumber, 2);
    expect(corrected.substitutions.single.setNumber, 2);
    expect(corrected.timeouts.single.setNumber, 1);
    expect(corrected.rotationAdjustments.single.setNumber, 1);
    expect(imported.rallies.first.setNumber, 1);
    final comparison = service.compare(primary, corrected);
    expect(comparison.conflicts, isEmpty);
    expect(
      service
          .merge(
            comparison,
            preferImported: const {},
            officialLogId: 'official',
            now: DateTime.utc(2026, 10, 2),
          )
          .rallies
          .map((item) => item.winnerTeamId),
      [homeTeam.id, awayTeam.id],
    );
    expect(
      () => service.remapSetNumbers(imported, const {1: 2}),
      throwsArgumentError,
    );
    expect(
      service.setSequenceError(
        service.remapSetNumbers(primary, const {1: 3}),
        3,
      ),
      contains('numbered consecutively'),
    );
  });

  test('set mappings survive revision JSON and old revisions still load', () {
    final revision = FinalizationRevision(
      id: 'revision',
      finalizedAt: DateTime.utc(2026, 10, 2),
      reason: 'Set labels corrected',
      officialLog: testLog(),
      setMappings: const {
        'log-b': {1: 2, 2: 1},
      },
    );
    expect(
      FinalizationRevision.fromJson(revision.toJson()).setMappings,
      revision.setMappings,
    );
    final oldJson = revision.toJson()..remove('setMappings');
    expect(FinalizationRevision.fromJson(oldJson).setMappings, isEmpty);
  });

  test('excluding rallies resequences a derived log and keeps the source', () {
    final source =
        testLog(
          rallies: [
            rally('r1', 1, homeTeam.id, 1, 0),
            rally('extra', 2, awayTeam.id, 1, 1),
            rally('r3', 3, homeTeam.id, 2, 1),
          ],
        ).copyWith(
          rotationAdjustments: [
            RotationAdjustment(
              id: 'rotation',
              teamId: homeTeam.id,
              setNumber: 1,
              afterRallySequence: 3,
              rotation: 2,
              recordedAt: DateTime.utc(2026, 10, 2),
            ),
          ],
        );
    final filtered = service.excludeRallies(source, {'extra'});
    expect(filtered.rallies.map((item) => item.id), ['r1', 'r3']);
    expect(filtered.rallies.map((item) => item.sequence), [1, 2]);
    expect(filtered.rotationAdjustments.single.afterRallySequence, 2);
    expect(source.rallies.length, 3);
    expect(source.rotationAdjustments.single.afterRallySequence, 3);
    expect(
      () => service.excludeRallies(source, {'unknown'}),
      throwsArgumentError,
    );
  });

  test('finalization applies set target and excluded rallies without rewriting logs', () async {
    final primary = testLog(
      rallies: [
        rally('a1', 1, homeTeam.id, 1, 0),
        rally('a2', 2, homeTeam.id, 2, 0),
        rally('extra', 3, homeTeam.id, 3, 0),
      ],
    );
    final imported = testLog(
      id: 'log-b',
      assignedTeamId: awayTeam.id,
      deviceId: 'device-b',
      rallies: [
        rally('b1', 1, homeTeam.id, 1, 0),
        rally('b2', 2, homeTeam.id, 2, 0),
      ],
    );
    final game = testGame(logs: [primary, imported]).copyWith(
      rulesSnapshot: const MatchRules(setsToWin: 1, maxSets: 1, winBy: 1),
    );
    final initial = AppData(
      deviceId: 'device-a',
      tournaments: [
        testTournament(games: [game]),
      ],
    );
    final repository = MemoryAppRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appRepositoryProvider.overrideWithValue(repository),
        initialAppDataProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await expectLater(
      controller.finalizeReconciliation(
        'tournament',
        'game',
        preferImported: const {},
        reason: 'Check',
        setTargets: const {1: 2},
      ),
      throwsA(isA<StateError>()),
    );
    await controller.finalizeReconciliation(
      'tournament',
      'game',
      preferImported: const {},
      reason: 'Remove extra',
      setTargets: const {1: 2},
      excludedRallyIds: const {
        'log-a': ['extra'],
      },
    );
    final saved = (await repository.load()).tournaments.single.games.single;
    expect(saved.status, GameStatus.finalized);
    expect(saved.logs.first.rallies.length, 3);
    expect(saved.officialLog!.rallies.map((item) => item.id), ['a1', 'a2']);
    expect(saved.rulesSnapshot!.targetForSet(1), 2);
    expect(saved.revisions.single.excludedRallyIds[primary.id], ['extra']);
    final roundTrip = AppData.decode((await repository.load()).encode())
        .tournaments
        .single
        .games
        .single;
    expect(roundTrip.rulesSnapshot!.setTargets, {1: 2});
    expect(roundTrip.revisions.single.excludedRallyIds[primary.id], ['extra']);
  });

  test(
    'finalization saves corrected set order without changing source logs',
    () async {
      final primary = testLog(
        rallies: [
          rally('a1', 1, homeTeam.id, 1, 0),
          rally('a2', 1, awayTeam.id, 0, 1, setNumber: 2),
          rally('a3', 1, homeTeam.id, 1, 0, setNumber: 3),
        ],
      );
      final imported = testLog(
        id: 'log-b',
        assignedTeamId: awayTeam.id,
        deviceId: 'device-b',
        rallies: [
          rally('b1', 1, awayTeam.id, 0, 1),
          rally('b2', 1, homeTeam.id, 1, 0, setNumber: 2),
          rally('b3', 1, homeTeam.id, 1, 0, setNumber: 3),
        ],
      );
      final game = testGame(logs: [primary, imported]).copyWith(
        rulesSnapshot: const MatchRules(
          setsToWin: 2,
          maxSets: 3,
          regularSetTarget: 1,
          decidingSetTarget: 1,
          winBy: 1,
        ),
      );
      final initial = AppData(
        deviceId: 'device-a',
        tournaments: [
          testTournament(games: [game]),
        ],
      );
      final repository = MemoryAppRepository(initial);
      final container = ProviderContainer(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(initial),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(appControllerProvider.notifier)
          .finalizeReconciliation(
            'tournament',
            'game',
            preferImported: const {},
            reason: 'Corrected swapped set labels',
            setMappings: const {
              'log-b': {1: 2, 2: 1},
            },
          );
      final saved = (await repository.load()).tournaments.single.games.single;
      expect(saved.status, GameStatus.finalized);
      expect(saved.logs[1].rallies.first.setNumber, 1);
      expect(saved.officialLog!.rallies.map((item) => item.winnerTeamId), [
        homeTeam.id,
        awayTeam.id,
        homeTeam.id,
      ]);
      expect(saved.revisions.single.setMappings['log-b'], {1: 2, 2: 1});
      expect(
        AppData.decode((await repository.load()).encode())
            .tournaments
            .single
            .games
            .single
            .revisions
            .single
            .setMappings['log-b'],
        {1: 2, 2: 1},
      );
    },
  );

  test('matching score streams have no conflicts and combine actions', () {
    final homeAction = TeamAction(
      id: 'a',
      teamId: 'home',
      playerId: 'home-0',
      skill: Skill.attack,
      grade: ActionGrade.success,
      recordedAt: DateTime.utc(2026, 10, 2),
    );
    final awayAction = TeamAction(
      id: 'b',
      teamId: 'away',
      playerId: 'away-0',
      skill: Skill.dig,
      grade: ActionGrade.positive,
      recordedAt: DateTime.utc(2026, 10, 2),
    );
    final primary = testLog(
      rallies: [
        rally('r1a', 1, 'home', 1, 0, actions: [homeAction]),
      ],
    );
    final imported = testLog(
      id: 'log-b',
      deviceId: 'device-b',
      assignedTeamId: 'away',
      rallies: [
        rally('r1b', 1, 'home', 1, 0, actions: [awayAction]),
      ],
    );
    final result = service.compare(primary, imported);
    expect(result.conflicts, isEmpty);
    final merged = service.merge(
      result,
      preferImported: {},
      officialLogId: 'official',
      now: DateTime.utc(2026, 10, 2),
    );
    expect(
      merged.rallies.single.actions.map((item) => item.id),
      containsAll(['a', 'b']),
    );
  });

  test('flags winner, score, and missing-rally disagreements', () {
    final primary = testLog(
      rallies: [rally('a1', 1, 'home', 1, 0), rally('a2', 2, 'away', 1, 1)],
    );
    final imported = testLog(
      id: 'log-b',
      deviceId: 'device-b',
      rallies: [rally('b1', 1, 'away', 0, 1)],
    );
    final result = service.compare(primary, imported);
    expect(
      result.conflicts.map((item) => item.kind),
      containsAll([ConflictKind.winner, ConflictKind.missingRally]),
    );
  });

  test('imported choice controls authoritative score', () {
    final primary = testLog(rallies: [rally('a1', 1, 'home', 1, 0)]);
    final imported = testLog(
      id: 'log-b',
      deviceId: 'device-b',
      rallies: [rally('b1', 1, 'away', 0, 1)],
    );
    final result = service.compare(primary, imported);
    final merged = service.merge(
      result,
      preferImported: {'1:1'},
      officialLogId: 'official',
      now: DateTime.utc(2026, 10, 2),
    );
    expect(merged.rallies.single.winnerTeamId, awayTeam.id);
  });

  test('missing-side choice keeps the available rally', () {
    final primary = testLog(rallies: [rally('a1', 1, 'home', 1, 0)]);
    final imported = testLog(
      id: 'log-b',
      deviceId: 'device-b',
      rallies: const [],
    );
    final result = service.compare(primary, imported);
    final merged = service.merge(
      result,
      preferImported: {'1:1'},
      officialLogId: 'official',
      now: DateTime.utc(2026, 10, 2),
    );

    expect(merged.rallies.single.id, 'a1');
  });

  test('manual rally override replaces score and actions', () {
    final primary = testLog(rallies: [rally('a1', 1, 'home', 1, 0)]);
    final imported = testLog(
      id: 'log-b',
      deviceId: 'device-b',
      rallies: [rally('b1', 1, 'home', 1, 0)],
    );
    final overrideAction = TeamAction(
      id: 'manual-action',
      teamId: awayTeam.id,
      playerId: awayTeam.players.first.id,
      skill: Skill.block,
      grade: ActionGrade.success,
      recordedAt: DateTime.utc(2026, 10, 2),
    );
    final override = Rally(
      id: 'manual-rally',
      setNumber: 1,
      sequence: 1,
      winnerTeamId: awayTeam.id,
      homeScore: 0,
      awayScore: 1,
      homeRotation: 1,
      awayRotation: 1,
      servingTeamId: awayTeam.id,
      recordedAt: DateTime.utc(2026, 10, 2),
      actions: [overrideAction],
      overrideReason: 'Corrected from the scoresheet',
    );
    final merged = service.merge(
      service.compare(primary, imported),
      preferImported: const {},
      officialLogId: 'official',
      now: DateTime.utc(2026, 10, 2),
      rallyOverrides: {'1:1': override},
    );

    expect(merged.rallies.single.id, 'manual-rally');
    expect(merged.rallies.single.awayScore, 1);
    expect(merged.rallies.single.actions.single.id, 'manual-action');
    expect(merged.rallies.single.overrideReason, isNotEmpty);
  });
}
