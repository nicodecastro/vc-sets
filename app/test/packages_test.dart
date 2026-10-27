import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/application/file_exchange.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/packages.dart';

import 'test_fixtures.dart';

String withDescendingSetMapping(String source) {
  final root = jsonDecode(source) as Map<String, dynamic>;
  final payload = jsonEncode(root['payload']);
  final mapping = RegExp(r'"[12]":[12],"[12]":[12]');
  if (!mapping.hasMatch(payload)) {
    throw StateError('Fixture needs a two-set correction.');
  }
  final windowsPayload = payload.replaceFirst(mapping, '"2":1,"1":2');
  final manifest = Map<String, dynamic>.from(
    root['manifest'] as Map,
  )..['payloadSha256'] = sha256.convert(utf8.encode(windowsPayload)).toString();
  return '{"manifest":${jsonEncode(manifest)},"payload":$windowsPayload}';
}

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

  test('backup can skip the hash but not format and package checks', () {
    final source = service.createBackup(
      packageId: 'backup',
      data: const AppData(deviceId: 'device-a'),
      exportedAt: DateTime.utc(2026, 10, 2),
    );
    final root = jsonDecode(source) as Map<String, dynamic>;
    root['payload']['deviceId'] = 'changed';
    final changed = jsonEncode(root);

    expect(() => service.decodeBackup(changed), throwsFormatException);
    expect(
      service.decodeBackup(changed, verifyIntegrity: false).deviceId,
      'changed',
    );
    expect(
      const FileExchangeService()
          .decodeBackupBytes(
            Uint8List.fromList(utf8.encode(changed)),
            verifyIntegrity: false,
          )
          .deviceId,
      'changed',
    );
    expect(
      () => service.decodeBackup(
        changed.substring(0, changed.length - 1),
        verifyIntegrity: false,
      ),
      throwsFormatException,
    );

    root['manifest']['type'] = 'game';
    expect(
      () => service.decodeBackup(jsonEncode(root), verifyIntegrity: false),
      throwsFormatException,
    );
    root['manifest']['type'] = 'backup';
    root['manifest']['schemaVersion'] =
        PortablePackageService.schemaVersion + 1;
    expect(
      () => service.decodeBackup(jsonEncode(root), verifyIntegrity: false),
      throwsFormatException,
    );
  });

  test('raw-order fallback validates an equivalent encoded payload', () {
    final data = AppData(deviceId: 'device-a');
    final source = service.createBackup(
      packageId: 'escaped-backup',
      data: data,
      exportedAt: DateTime.utc(2026, 10, 2),
    );
    final escapedPayload = jsonEncode(data.toJson())
        .replaceFirst('device-a', r'device\u002da');
    final originalHash =
        (jsonDecode(source) as Map)['manifest']['payloadSha256'] as String;
    final escapedHash = sha256.convert(utf8.encode(escapedPayload)).toString();
    final escapedSource = source
        .replaceFirst('"deviceId": "device-a"', r'"deviceId": "device\u002da"')
        .replaceFirst(originalHash, escapedHash);
    final decodedHashSource = source.replaceFirst(
      '"deviceId": "device-a"',
      r'"deviceId": "device\u002da"',
    );

    expect(escapedHash, isNot(originalHash));
    expect(service.decodeBackup(escapedSource).deviceId, 'device-a');
    expect(service.decodeBackup(decodedHashSource).deviceId, 'device-a');
    expect(
      () => service.decodeBackup(
        escapedSource.replaceFirst(
          r'"deviceId": "device\u002da"',
          '"deviceId": "changed"',
        ),
      ),
      throwsFormatException,
    );
  });

  test('backup and game package retain descending set-mapping keys', () {
    final official = testLog(id: 'official');
    final game = testGame(logs: [testLog()], officialLog: official).copyWith(
      revisions: [
        FinalizationRevision(
          id: 'revision',
          finalizedAt: DateTime.utc(2026, 10, 2),
          reason: 'Corrected set order',
          officialLog: official,
          setMappings: const {
            'log-a': {2: 1, 1: 2},
          },
        ),
      ],
    );
    final tournament = testTournament(games: [game]);
    final data = AppData(deviceId: 'device-a', tournaments: [tournament]);
    final backup = withDescendingSetMapping(
      service.createBackup(
        packageId: 'mapped-backup',
        data: data,
        exportedAt: DateTime.utc(2026, 10, 2),
      ),
    );
    final package = service.createGamePackage(
      packageId: 'mapped-game',
      deviceId: 'device-a',
      exportedAt: DateTime.utc(2026, 10, 2),
      tournament: tournament,
      game: game,
      log: game.logs.first,
    );

    final gamePackage = withDescendingSetMapping(package.encode());
    expect(backup, contains('"2":1,"1":2'));
    expect(
      service
          .decodeBackup(backup)
          .tournaments
          .single
          .games
          .single
          .revisions
          .single
          .setMappings['log-a'],
      {2: 1, 1: 2},
    );
    expect(
      service
          .decodeGamePackage(gamePackage)
          .tournament
          .games
          .single
          .revisions
          .single
          .setMappings['log-a'],
      {2: 1, 1: 2},
    );
    expect(
      () => service.decodeBackup(
        backup.replaceFirst('"deviceId":"device-a"', '"deviceId":"changed"'),
      ),
      throwsFormatException,
    );
    final alteredGamePackage = gamePackage.replaceFirst(
      '"gameId":"game"',
      '"gameId":"changed"',
    );
    expect(alteredGamePackage, isNot(gamePackage));
    expect(
      () => service.decodeGamePackage(alteredGamePackage),
      throwsFormatException,
    );
    final rootEnd = backup.lastIndexOf('}');
    final duplicatePayload =
        '${backup.substring(0, rootEnd)}, "payload": ${jsonEncode(data.toJson())}}';
    expect(() => service.decodeBackup(duplicatePayload), throwsFormatException);
    final duplicateGamePayload =
        '${gamePackage.substring(0, gamePackage.length - 1)},"payload":{}}';
    expect(
      () => service.decodeGamePackage(duplicateGamePayload),
      throwsFormatException,
    );
    expect(
      () => service.decodeBackup(backup.substring(0, backup.length - 1)),
      throwsFormatException,
    );
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

  test('R-5 CSV exports both teams, every sheet, and their substitutions', () {
    final now = DateTime.utc(2026, 10, 2, 10);
    final homeWithBench = homeTeam.copyWith(
      players: [
        ...homeTeam.players,
        const Player(
          id: 'bench',
          number: 19,
          name: 'Santos, Bea',
          position: PlayerPosition.U,
        ),
      ],
    );
    final homeLineup = LineupSnapshot(
      teamId: homeTeam.id,
      playerIds: homeTeam.players.map((player) => player.id).toList(),
      recordedAt: now,
    );
    final revisedLineup = LineupSnapshot(
      teamId: homeTeam.id,
      playerIds: [
        homeTeam.players[1].id,
        homeTeam.players[0].id,
        ...homeTeam.players.skip(2).map((player) => player.id),
      ],
      recordedAt: now.add(const Duration(minutes: 1)),
    );
    final awayLineup = LineupSnapshot(
      teamId: awayTeam.id,
      playerIds: awayTeam.players.map((player) => player.id).toList(),
      recordedAt: now,
    );
    final substitution = Substitution(
      id: 'sub',
      teamId: homeTeam.id,
      setNumber: 1,
      playerOutId: homeTeam.players.first.id,
      playerInId: 'bench',
      homeScore: 8,
      awayScore: 6,
      recordedAt: now.add(const Duration(minutes: 2)),
    );
    final homeLog = testLog(id: 'home-log').copyWith(
      lineups: [homeLineup, revisedLineup],
      substitutions: [substitution],
    );
    final awayLog = testLog(
      id: 'away-log',
      assignedTeamId: awayTeam.id,
    ).copyWith(lineups: [awayLineup]);
    final official = testLog(id: 'official', assignedTeamId: 'official')
        .copyWith(
          lineups: [homeLineup, revisedLineup, awayLineup],
          substitutions: [substitution],
        );
    final finalized = testGame(logs: [homeLog, awayLog], officialLog: official);
    final nextGame = Game(
      id: 'next-game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: now.add(const Duration(days: 1)),
      venue: 'Main Court',
      status: GameStatus.inProgress,
      logs: [
        ScorerLog(
          id: 'next-log',
          gameId: 'next-game',
          assignedTeamId: homeTeam.id,
          deviceId: 'device-a',
          createdAt: now,
          updatedAt: now,
          initialServingTeamId: homeTeam.id,
          lineups: [
            LineupSnapshot(
              teamId: homeTeam.id,
              setNumber: 2,
              playerIds: homeLineup.playerIds,
              recordedAt: now.add(const Duration(days: 1)),
            ),
          ],
        ),
      ],
    );
    final tournament = testTournament(games: [finalized, nextGame])
        .copyWith(teams: [homeWithBench, awayTeam]);

    final csv = const FileExchangeService().r5AndSubsCsv(tournament);
    final lines = const LineSplitter().convert(csv);

    expect(lines, hasLength(6));
    expect(lines.first, contains('Rotation,I,II,III,IV,V,VI,Player out'));
    expect(csv, contains('"game","2026-10-02T00:00:00.000Z"'));
    expect(csv, contains('"Home Club",1,"R-5"'));
    expect(csv, contains('"Away Club",1,"R-5"'));
    expect(csv, contains('"#1 Home 1"'));
    expect(csv, contains('"#7 Away 1"'));
    expect(csv, contains('"#19 Santos, Bea",8,6,"Regular","No"'));
    expect(csv, contains('"next-game"'));
    expect(csv, contains('"Home Club",2,"R-5"'));
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
