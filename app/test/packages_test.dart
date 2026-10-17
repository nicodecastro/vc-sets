import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/application/file_exchange.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/packages.dart';

import 'test_fixtures.dart';

void main() {
  const service = PortablePackageService();

  test('game package round trips with integrity metadata', () {
    final game = testGame(logs: [testLog()]);
    final tournament = testTournament(games: [game]);
    final package = service.createGamePackage(
      packageId: 'package-1',
      deviceId: 'device-a',
      exportedAt: DateTime.utc(2026, 10, 2),
      tournament: tournament,
      game: game,
      log: game.logs.single,
    );
    final decoded = service.decodeGamePackage(package.encode());
    expect(decoded.manifest.packageId, 'package-1');
    expect(decoded.log?.id, 'log-a');
    expect(decoded.tournament.teams, hasLength(2));
  });

  test('tampered payload is rejected', () {
    final data = AppData(deviceId: 'device-a', tournaments: [testTournament()]);
    final source = service.createBackup(
      packageId: 'backup',
      data: data,
      exportedAt: DateTime.utc(2026, 10, 2),
    );
    final root = jsonDecode(source) as Map<String, dynamic>;
    root['payload']['deviceId'] = 'tampered';
    expect(() => service.decodeBackup(jsonEncode(root)), throwsFormatException);
  });

  test('full backup round trips tournament data', () {
    final data = AppData(
      deviceId: 'device-a',
      tournaments: [testTournament()],
      importedPackageIds: const ['one'],
    );
    final source = service.createBackup(
      packageId: 'backup',
      data: data,
      exportedAt: DateTime.utc(2026, 10, 2),
    );
    final restored = service.decodeBackup(source);
    expect(restored.tournaments.single.name, 'Club Cup');
    expect(restored.importedPackageIds, ['one']);
  });

  test('backup preserves per-set targets and reconciliation exclusions', () {
    final official = testLog(id: 'official');
    final game = testGame(logs: [testLog()], officialLog: official).copyWith(
      rulesSnapshot: const MatchRules(setTargets: {2: 21}),
      revisions: [
        FinalizationRevision(
          id: 'revision',
          finalizedAt: DateTime.utc(2026, 10, 2),
          reason: 'Corrected scores',
          officialLog: official,
          setTargets: const {2: 21},
          excludedRallyIds: const {
            'log-a': ['extra'],
          },
        ),
      ],
    );
    final data = AppData(
      deviceId: 'device-a',
      tournaments: [
        testTournament(games: [game]),
      ],
    );
    final restored = service.decodeBackup(
      service.createBackup(
        packageId: 'corrected-backup',
        data: data,
        exportedAt: DateTime.utc(2026, 10, 2),
      ),
    );
    final saved = restored.tournaments.single.games.single;
    expect(saved.rulesSnapshot!.setTargets, {2: 21});
    expect(saved.revisions.single.excludedRallyIds, {
      'log-a': ['extra'],
    });
  });

  test('legacy UT player positions restore as U', () {
    final player = Player.fromJson(const {
      'id': 'utility',
      'number': 8,
      'name': 'Utility Player',
      'position': 'UT',
    });

    expect(player.position, PlayerPosition.U);
    expect(player.toJson()['position'], 'U');
  });

  test('backup byte import accepts a UTF-8 byte-order mark', () {
    final source = service.createBackup(
      packageId: 'bom-backup',
      data: AppData(deviceId: 'device-a', tournaments: [testTournament()]),
      exportedAt: DateTime.utc(2026, 10, 3),
    );
    final bytes = Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(source),
    ]);

    final restored = const FileExchangeService().decodeBackupBytes(bytes);

    expect(restored.deviceId, 'device-a');
    expect(restored.tournaments.single.name, 'Club Cup');
  });

  test('backup preserves pools, phase rules, and third-place games', () {
    const oneSet = MatchRules(setsToWin: 1, maxSets: 1);
    const bestOfThree = MatchRules(setsToWin: 2, maxSets: 3);
    final tournament = Tournament(
      id: 'phased',
      name: 'Phased Cup',
      venue: 'Gym',
      startsOn: DateTime.utc(2026, 10, 2),
      endsOn: DateTime.utc(2026, 10, 3),
      createdAt: DateTime.utc(2026, 9, 1),
      format: TournamentFormat.poolsThenKnockout,
      poolCount: 2,
      qualifiersPerPool: 2,
      thirdPlaceEnabled: true,
      poolRules: oneSet,
      thirdPlaceRules: bestOfThree,
      teams: [
        homeTeam.copyWith(poolNumber: 1),
        awayTeam.copyWith(poolNumber: 2),
      ],
      games: [
        Game(
          id: 'bronze',
          tournamentId: 'phased',
          homeTeamId: homeTeam.id,
          awayTeamId: awayTeam.id,
          scheduledAt: DateTime.utc(2026, 10, 3),
          venue: 'Gym',
          stage: GameStage.bracket,
          bracketRound: 2,
          bracketType: BracketGameType.thirdPlace,
          rulesSnapshot: bestOfThree,
        ),
      ],
    );
    final source = service.createBackup(
      packageId: 'phased-backup',
      data: AppData(deviceId: 'device-a', tournaments: [tournament]),
      exportedAt: DateTime.utc(2026, 10, 2),
    );

    final restored = service.decodeBackup(source).tournaments.single;
    expect(restored.format, TournamentFormat.poolsThenKnockout);
    expect(restored.poolCount, 2);
    expect(restored.thirdPlaceEnabled, isTrue);
    expect(restored.poolRules?.setsToWin, 1);
    expect(restored.poolRules?.maxSets, 1);
    expect(restored.teams.last.poolNumber, 2);
    expect(restored.games.single.bracketType, BracketGameType.thirdPlace);
    expect(restored.games.single.rulesSnapshot?.maxSets, 3);
  });

  test('game package preserves lineup, substitution, and timeout events', () {
    final now = DateTime.utc(2026, 10, 2);
    final log = ScorerLog(
      id: 'event-log',
      gameId: 'game',
      assignedTeamId: homeTeam.id,
      deviceId: 'device-a',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: homeTeam.id,
      lineups: [
        LineupSnapshot(
          teamId: homeTeam.id,
          playerIds: homeTeam.players.map((player) => player.id).toList(),
          recordedAt: now,
        ),
      ],
      substitutions: [
        Substitution(
          id: 'sub-1',
          teamId: homeTeam.id,
          setNumber: 1,
          playerOutId: homeTeam.players.first.id,
          playerInId: 'bench',
          homeScore: 4,
          awayScore: 3,
          recordedAt: now,
          kind: SubstitutionKind.liberoReplacement,
        ),
      ],
      timeouts: [
        TeamTimeout(
          id: 'timeout-1',
          teamId: homeTeam.id,
          setNumber: 1,
          homeScore: 8,
          awayScore: 9,
          recordedAt: now,
        ),
      ],
    );
    final game = testGame(logs: [log]);
    final package = service.createGamePackage(
      packageId: 'events-package',
      deviceId: 'device-a',
      exportedAt: now,
      tournament: testTournament(games: [game]),
      game: game,
      log: log,
    );

    final decoded = service.decodeGamePackage(package.encode()).log!;
    expect(decoded.lineups.single.setNumber, 1);
    expect(decoded.substitutions.single.playerInId, 'bench');
    expect(decoded.substitutions.single.isLiberoReplacement, isTrue);
    expect(decoded.timeouts.single.homeScore, 8);
  });
}
