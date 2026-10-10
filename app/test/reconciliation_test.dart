import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/reconciliation.dart';

import 'test_fixtures.dart';

Rally rally(
  String id,
  int sequence,
  String winner,
  int home,
  int away, {
  List<TeamAction> actions = const [],
}) => Rally(
  id: id,
  setNumber: 1,
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
