import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/application/providers.dart';
import 'package:vc_sets/data/repository.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/packages.dart';
import 'package:vc_sets/domain/scoring.dart';

import 'test_fixtures.dart';

ScorerLog _completedSweep({
  required String gameId,
  required String homeId,
  required String awayId,
  required String winnerId,
  int setsWon = 3,
}) {
  final homeWon = winnerId == homeId;
  return ScorerLog(
    id: 'official-$gameId',
    gameId: gameId,
    assignedTeamId: 'official',
    deviceId: 'device',
    createdAt: DateTime.utc(2026, 10, 2),
    updatedAt: DateTime.utc(2026, 10, 2),
    initialServingTeamId: homeId,
    rallies: [
      for (var set = 1; set <= setsWon; set++)
        Rally(
          id: '$gameId-$set',
          setNumber: set,
          sequence: 1,
          winnerTeamId: winnerId,
          homeScore: homeWon ? 25 : 0,
          awayScore: homeWon ? 0 : 25,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: winnerId,
          recordedAt: DateTime.utc(2026, 10, 2),
        ),
    ],
  );
}

void main() {
  test(
    'controller persists tournament, roster, and generated fixtures',
    () async {
      final initial = const AppData(deviceId: 'device');
      final repository = MemoryAppRepository(initial);
      final container = ProviderContainer(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(initial),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      final tournamentId = await controller.createTournament(
        name: 'League',
        venue: 'Gym',
        startsOn: DateTime.utc(2026, 10, 2),
        endsOn: DateTime.utc(2026, 10, 2),
      );
      await controller.addTeam(tournamentId, 'Alpha', 'ALP', 0xFF000000);
      await controller.addTeam(tournamentId, 'Beta', 'BET', 0xFFFFFFFF);
      final team = container
          .read(appControllerProvider)
          .tournaments
          .single
          .teams
          .first;
      await controller.addPlayer(
        tournamentId,
        team.id,
        number: 1,
        name: 'Setter',
        position: PlayerPosition.S,
      );
      await controller.generateRoundRobin(tournamentId);

      final persisted = await repository.load();
      expect(
        persisted.tournaments.single.teams.first.players.single.name,
        'Setter',
      );
      expect(persisted.tournaments.single.games, hasLength(1));
    },
  );

  test('edits tournament metadata without rewriting fixtures', () async {
    final initial = const AppData(deviceId: 'device');
    final repository = MemoryAppRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appRepositoryProvider.overrideWithValue(repository),
        initialAppDataProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    final id = await controller.createTournament(
      name: 'Old name',
      venue: 'Old gym',
      startsOn: DateTime.utc(2026, 10, 2),
      endsOn: DateTime.utc(2026, 10, 2),
    );
    await controller.addTeam(id, 'Alpha', 'ALP', 0xFF000000);
    await controller.addTeam(id, 'Beta', 'BET', 0xFFFFFFFF);
    await controller.generateRoundRobin(id);
    final originalGame = container
        .read(appControllerProvider)
        .tournaments
        .single
        .games
        .single;

    await controller.updateTournamentDetails(
      id,
      name: 'New name',
      venue: 'New gym',
      startsOn: DateTime.utc(2026, 10, 3),
      endsOn: DateTime.utc(2026, 10, 5),
      status: TournamentStatus.completed,
    );

    final edited = (await repository.load()).tournaments.single;
    expect(edited.name, 'New name');
    expect(edited.venue, 'New gym');
    expect(edited.startsOn, DateTime.utc(2026, 10, 3));
    expect(edited.endsOn, DateTime.utc(2026, 10, 5));
    expect(edited.status, TournamentStatus.completed);
    expect(edited.games.single.venue, originalGame.venue);
    expect(edited.games.single.scheduledAt, originalGame.scheduledAt);
  });

  test('deletes a tournament and all of its nested data', () async {
    final tournament = testTournament(
      games: [
        testGame(logs: [testLog()]),
      ],
    );
    final initial = AppData(deviceId: 'device', tournaments: [tournament]);
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
        .deleteTournament(tournament.id);

    expect(container.read(appControllerProvider).tournaments, isEmpty);
    expect((await repository.load()).tournaments, isEmpty);
  });

  test(
    'replaces a roster while preserving player identities and captain',
    () async {
      final initial = const AppData(deviceId: 'device');
      final repository = MemoryAppRepository(initial);
      final container = ProviderContainer(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(initial),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      final tournamentId = await controller.createTournament(
        name: 'League',
        venue: 'Gym',
        startsOn: DateTime.utc(2026, 10, 2),
        endsOn: DateTime.utc(2026, 10, 2),
      );
      await controller.addTeam(tournamentId, 'Alpha', 'ALP', 0xFF000000);
      final team = container
          .read(appControllerProvider)
          .tournaments
          .single
          .teams
          .single;
      await controller.addPlayer(
        tournamentId,
        team.id,
        number: 1,
        name: 'Original',
        position: PlayerPosition.S,
      );
      final original = container
          .read(appControllerProvider)
          .tournaments
          .single
          .teams
          .single
          .players
          .single;

      await controller.replaceTeamRoster(tournamentId, team.id, [
        Player(
          id: original.id,
          number: 7,
          name: 'Updated',
          position: PlayerPosition.OH,
          isCaptain: true,
        ),
        const Player(
          id: 'new-player',
          number: 8,
          name: 'New player',
          position: PlayerPosition.MB,
        ),
      ]);

      final roster =
          (await repository.load()).tournaments.single.teams.single.players;
      expect(roster, hasLength(2));
      expect(roster.first.id, original.id);
      expect(roster.first.number, 7);
      expect(roster.first.isCaptain, isTrue);
    },
  );

  test('deletes a game and persists its removal', () async {
    final initial = const AppData(deviceId: 'device');
    final repository = MemoryAppRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appRepositoryProvider.overrideWithValue(repository),
        initialAppDataProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    final tournamentId = await controller.createTournament(
      name: 'League',
      venue: 'Gym',
      startsOn: DateTime.utc(2026, 10, 2),
      endsOn: DateTime.utc(2026, 10, 2),
    );
    await controller.addTeam(tournamentId, 'Alpha', 'ALP', 0xFF000000);
    await controller.addTeam(tournamentId, 'Beta', 'BET', 0xFFFFFFFF);
    await controller.generateRoundRobin(tournamentId);
    final gameId = container
        .read(appControllerProvider)
        .tournaments
        .single
        .games
        .single
        .id;

    await controller.deleteGame(tournamentId, gameId);

    expect((await repository.load()).tournaments.single.games, isEmpty);
  });

  test('edits and reorders teams without changing their identities', () async {
    final initial = const AppData(deviceId: 'device');
    final repository = MemoryAppRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appRepositoryProvider.overrideWithValue(repository),
        initialAppDataProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    final tournamentId = await controller.createTournament(
      name: 'League',
      venue: 'Gym',
      startsOn: DateTime.utc(2026, 10, 2),
      endsOn: DateTime.utc(2026, 10, 2),
    );
    await controller.addTeam(tournamentId, 'Alpha', 'ALP', 0xFF000000);
    await controller.addTeam(tournamentId, 'Beta', 'BET', 0xFFFFFFFF);
    final originalTeams = container
        .read(appControllerProvider)
        .tournaments
        .single
        .teams;

    await controller.updateTeamDetails(
      tournamentId,
      originalTeams.first.id,
      name: 'Alpha Updated',
      shortCode: 'AU',
    );
    await controller.reorderTeams(tournamentId, 0, 1);

    final teams = (await repository.load()).tournaments.single.teams;
    expect(teams.first.id, originalTeams.last.id);
    expect(teams.last.id, originalTeams.first.id);
    expect(teams.last.name, 'Alpha Updated');
    expect(teams.last.shortCode, 'AU');
  });

  test('generates a top-two final from completed pool standings', () async {
    final official = _completedSweep(
      gameId: 'pool-game',
      homeId: homeTeam.id,
      awayId: awayTeam.id,
      winnerId: homeTeam.id,
    );
    final poolGame = Game(
      id: 'pool-game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: DateTime.utc(2026, 10, 2),
      venue: 'Gym',
      status: GameStatus.finalized,
      officialLog: official,
    );
    final tournament = Tournament(
      id: 'tournament',
      name: 'League',
      venue: 'Gym',
      startsOn: DateTime.utc(2026, 10, 2),
      endsOn: DateTime.utc(2026, 10, 2),
      createdAt: DateTime.utc(2026, 9, 1),
      teams: [homeTeam, awayTeam],
      games: [poolGame],
      bracketEnabled: true,
      bracketSize: 2,
    );
    final initial = AppData(deviceId: 'device', tournaments: [tournament]);
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
        .generateBracket('tournament');

    final bracketGames = (await repository.load()).tournaments.single.games
        .where((game) => game.stage == GameStage.bracket)
        .toList();
    expect(bracketGames, hasLength(1));
    expect(bracketGames.single.homeTeamId, homeTeam.id);
    expect(bracketGames.single.awayTeamId, awayTeam.id);
    expect(bracketGames.single.bracketRound, 1);
  });

  test('advances finalized semifinals into a final', () async {
    const thirdTeam = TournamentTeam(
      id: 'third',
      name: 'Third Club',
      shortCode: 'THR',
      colorValue: 0xFF123456,
    );
    const fourthTeam = TournamentTeam(
      id: 'fourth',
      name: 'Fourth Club',
      shortCode: 'FOR',
      colorValue: 0xFF654321,
    );
    final firstSemiLog = _completedSweep(
      gameId: 'semi-1',
      homeId: homeTeam.id,
      awayId: fourthTeam.id,
      winnerId: homeTeam.id,
    );
    final secondSemiLog = _completedSweep(
      gameId: 'semi-2',
      homeId: awayTeam.id,
      awayId: thirdTeam.id,
      winnerId: thirdTeam.id,
    );
    final tournament = Tournament(
      id: 'tournament',
      name: 'League',
      venue: 'Gym',
      startsOn: DateTime.utc(2026, 10, 2),
      endsOn: DateTime.utc(2026, 10, 2),
      createdAt: DateTime.utc(2026, 9, 1),
      bracketEnabled: true,
      bracketSize: 4,
      teams: [homeTeam, awayTeam, thirdTeam, fourthTeam],
      games: [
        Game(
          id: 'semi-1',
          tournamentId: 'tournament',
          homeTeamId: homeTeam.id,
          awayTeamId: fourthTeam.id,
          scheduledAt: DateTime.utc(2026, 10, 2, 10),
          venue: 'Gym',
          stage: GameStage.bracket,
          bracketRound: 1,
          bracketOrder: 0,
          status: GameStatus.finalized,
          officialLog: firstSemiLog,
        ),
        Game(
          id: 'semi-2',
          tournamentId: 'tournament',
          homeTeamId: awayTeam.id,
          awayTeamId: thirdTeam.id,
          scheduledAt: DateTime.utc(2026, 10, 2, 12),
          venue: 'Gym',
          stage: GameStage.bracket,
          bracketRound: 1,
          bracketOrder: 1,
          status: GameStatus.finalized,
          officialLog: secondSemiLog,
        ),
      ],
    );
    final initial = AppData(deviceId: 'device', tournaments: [tournament]);
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
        .advanceBracket('tournament');

    final finalGame = (await repository.load()).tournaments.single.games
        .singleWhere((game) => game.bracketRound == 2);
    expect(finalGame.stage, GameStage.bracket);
    expect(finalGame.homeTeamId, homeTeam.id);
    expect(finalGame.awayTeamId, thirdTeam.id);
    expect(finalGame.status, GameStatus.scheduled);
  });

  test('two pools advance crossover semifinalists with final and third-place rules', () async {
    const poolRules = MatchRules(setsToWin: 2, maxSets: 3);
    const knockoutRules = MatchRules(setsToWin: 3, maxSets: 5);
    final teams = [
      for (var pool = 1; pool <= 2; pool++)
        for (var seed = 1; seed <= 4; seed++)
          TournamentTeam(
            id: '${pool == 1 ? 'A' : 'B'}$seed',
            name: 'Pool ${pool == 1 ? 'A' : 'B'} Team $seed',
            shortCode: '${pool == 1 ? 'A' : 'B'}$seed',
            colorValue: 0xFF123456,
            poolNumber: pool,
          ),
    ];
    final poolGames = <Game>[];
    for (var pool = 1; pool <= 2; pool++) {
      final poolTeams = teams.where((team) => team.poolNumber == pool).toList();
      for (var home = 0; home < poolTeams.length; home++) {
        for (var away = home + 1; away < poolTeams.length; away++) {
          final id = 'pool-$pool-$home-$away';
          poolGames.add(
            Game(
              id: id,
              tournamentId: 'tournament',
              homeTeamId: poolTeams[home].id,
              awayTeamId: poolTeams[away].id,
              scheduledAt: DateTime.utc(2026, 10, 2, 8 + poolGames.length),
              venue: 'Gym',
              poolNumber: pool,
              rulesSnapshot: poolRules,
              status: GameStatus.finalized,
              officialLog: _completedSweep(
                gameId: id,
                homeId: poolTeams[home].id,
                awayId: poolTeams[away].id,
                winnerId: poolTeams[home].id,
                setsWon: 2,
              ),
            ),
          );
        }
      }
    }
    final tournament = Tournament(
      id: 'tournament',
      name: 'Two-pool cup',
      venue: 'Gym',
      startsOn: DateTime.utc(2026, 10, 2),
      endsOn: DateTime.utc(2026, 10, 3),
      createdAt: DateTime.utc(2026, 9, 1),
      format: TournamentFormat.poolsThenKnockout,
      poolCount: 2,
      qualifiersPerPool: 2,
      thirdPlaceEnabled: true,
      poolRules: poolRules,
      semifinalRules: knockoutRules,
      finalRules: knockoutRules,
      thirdPlaceRules: poolRules,
      teams: teams,
      games: poolGames,
    );
    final initial = AppData(deviceId: 'device', tournaments: [tournament]);
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
        .generateBracket('tournament');

    final generated = (await repository.load()).tournaments.single;
    final semifinals = generated.games
        .where((game) => game.stage == GameStage.bracket)
        .toList();
    expect(semifinals, hasLength(2));
    expect(semifinals.map((game) => '${game.homeTeamId}-${game.awayTeamId}'), [
      'A1-B2',
      'B1-A2',
    ]);
    expect(
      semifinals.every((game) => game.rulesSnapshot?.maxSets == 5),
      isTrue,
    );

    final completedSemifinals = [
      for (var index = 0; index < semifinals.length; index++)
        semifinals[index].copyWith(
          status: GameStatus.finalized,
          officialLog: _completedSweep(
            gameId: semifinals[index].id,
            homeId: semifinals[index].homeTeamId,
            awayId: semifinals[index].awayTeamId,
            winnerId: index == 0
                ? semifinals[index].homeTeamId
                : semifinals[index].awayTeamId,
          ),
        ),
    ];
    final completedTournament = generated.copyWith(
      games: [
        ...generated.games.where((game) => game.stage == GameStage.pool),
        ...completedSemifinals,
      ],
    );
    final completedData = AppData(
      deviceId: 'device',
      tournaments: [completedTournament],
    );
    final advancementRepository = MemoryAppRepository(completedData);
    final advancementContainer = ProviderContainer(
      overrides: [
        appRepositoryProvider.overrideWithValue(advancementRepository),
        initialAppDataProvider.overrideWithValue(completedData),
      ],
    );
    addTearDown(advancementContainer.dispose);

    await advancementContainer
        .read(appControllerProvider.notifier)
        .advanceBracket('tournament');

    final advanced = (await advancementRepository.load()).tournaments.single;
    final finalGame = advanced.games.singleWhere(
      (game) => game.bracketType == BracketGameType.finalMatch,
    );
    final thirdPlace = advanced.games.singleWhere(
      (game) => game.bracketType == BracketGameType.thirdPlace,
    );
    expect('${finalGame.homeTeamId}-${finalGame.awayTeamId}', 'A1-A2');
    expect(finalGame.rulesSnapshot?.maxSets, 5);
    expect('${thirdPlace.homeTeamId}-${thirdPlace.awayTeamId}', 'B2-B1');
    expect(thirdPlace.rulesSnapshot?.maxSets, 3);
    expect(thirdPlace.scheduledAt.isBefore(finalGame.scheduledAt), isTrue);
  });

  test(
    'records R-5 lineups, substitutions, and two timeouts per set',
    () async {
      const benchPlayer = Player(
        id: 'home-bench',
        number: 20,
        name: 'Bench Player',
        position: PlayerPosition.OH,
      );
      final trackedHome = homeTeam.copyWith(
        players: [...homeTeam.players, benchPlayer],
      );
      final game = Game(
        id: 'game',
        tournamentId: 'tournament',
        homeTeamId: trackedHome.id,
        awayTeamId: awayTeam.id,
        scheduledAt: DateTime.utc(2026, 10, 2),
        venue: 'Gym',
      );
      final tournament = Tournament(
        id: 'tournament',
        name: 'League',
        venue: 'Gym',
        startsOn: DateTime.utc(2026, 10, 2),
        endsOn: DateTime.utc(2026, 10, 2),
        createdAt: DateTime.utc(2026, 9, 1),
        teams: [trackedHome, awayTeam],
        games: [game],
      );
      final initial = AppData(deviceId: 'device', tournaments: [tournament]);
      final repository = MemoryAppRepository(initial);
      final container = ProviderContainer(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(initial),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);

      await controller.startScorerLog(
        'tournament',
        'game',
        assignedTeamId: trackedHome.id,
        initialServingTeamId: trackedHome.id,
      );
      final serviceOrder = trackedHome.players
          .take(6)
          .map((p) => p.id)
          .toList();
      await controller.setLineup(
        'tournament',
        'game',
        setNumber: 1,
        playerIds: serviceOrder,
      );
      await controller.recordSubstitution(
        'tournament',
        'game',
        playerOutId: serviceOrder.first,
        playerInId: benchPlayer.id,
      );
      await controller.recordTimeout('tournament', 'game');
      await controller.recordTimeout('tournament', 'game');

      final log =
          (await repository.load()).tournaments.single.games.single.logs.single;
      expect(log.substitutions, hasLength(1));
      expect(log.timeouts, hasLength(2));
      expect(log.serviceOrderFor(trackedHome.id, 1).first, benchPlayer.id);
      expect(log.courtOrderFor(trackedHome.id, 1, 2).last, benchPlayer.id);
      await expectLater(
        controller.recordTimeout('tournament', 'game'),
        throwsStateError,
      );
    },
  );

  test('requires a saved R-5 lineup before scoring each set', () async {
    const rules = MatchRules(
      setsToWin: 2,
      maxSets: 3,
      regularSetTarget: 1,
      decidingSetTarget: 1,
      winBy: 1,
    );
    final game = testGame().copyWith(rulesSnapshot: rules);
    final initial = AppData(
      deviceId: 'device',
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
    await controller.startScorerLog(
      'tournament',
      'game',
      assignedTeamId: homeTeam.id,
      initialServingTeamId: homeTeam.id,
    );
    var log =
        (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.lineups, isEmpty);
    await expectLater(
      controller.awardRally(
        'tournament',
        'game',
        winnerTeamId: homeTeam.id,
        actions: const [],
      ),
      throwsStateError,
    );
    await expectLater(
      controller.recordTimeout('tournament', 'game'),
      throwsStateError,
    );

    final players = homeTeam.players.map((player) => player.id).toList();
    await controller.setLineup(
      'tournament',
      'game',
      setNumber: 1,
      playerIds: players,
    );
    await controller.awardRally(
      'tournament',
      'game',
      winnerTeamId: homeTeam.id,
      actions: const [],
    );
    log = (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.lineupFor(homeTeam.id, 2), isNull);
    expect(log.courtOrderFor(homeTeam.id, 2, 1), isEmpty);
    await expectLater(
      controller.awardRally(
        'tournament',
        'game',
        winnerTeamId: homeTeam.id,
        actions: const [],
      ),
      throwsStateError,
    );

    await controller.setLineup(
      'tournament',
      'game',
      setNumber: 2,
      playerIds: players,
    );
    await controller.awardRally(
      'tournament',
      'game',
      winnerTeamId: homeTeam.id,
      actions: const [],
    );
    log = (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.rallies.map((rally) => rally.setNumber), [1, 2]);
  });

  test(
    'manual rotation persists and normal side-out rotation still applies',
    () async {
      final game = testGame();
      final initial = AppData(
        deviceId: 'device',
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
      await controller.startScorerLog(
        'tournament',
        'game',
        assignedTeamId: homeTeam.id,
        initialServingTeamId: homeTeam.id,
      );
      await expectLater(
        controller.rotateLineupManually('tournament', 'game'),
        throwsStateError,
      );
      await controller.setLineup(
        'tournament',
        'game',
        setNumber: 1,
        playerIds: homeTeam.players.map((player) => player.id).toList(),
      );
      await controller.rotateLineupManually('tournament', 'game');
      var saved = (await repository.load()).tournaments.single.games.single;
      var log = ScorerLog.fromJson(saved.logs.single.toJson());
      var score = const ScoringEngine().score(saved, log, const MatchRules());
      expect(score.homePoints, 0);
      expect(score.homeRotation, 2);
      expect(
        log.courtOrderFor(homeTeam.id, 1, score.homeRotation).last,
        homeTeam.players.first.id,
      );

      await controller.awardRally(
        'tournament',
        'game',
        winnerTeamId: awayTeam.id,
        actions: const [],
      );
      saved = (await repository.load()).tournaments.single.games.single;
      log = saved.logs.single;
      score = const ScoringEngine().score(saved, log, const MatchRules());
      expect(score.homeRotation, 2);
      expect(score.awayRotation, 2);
      await controller.awardRally(
        'tournament',
        'game',
        winnerTeamId: homeTeam.id,
        actions: const [],
      );
      saved = (await repository.load()).tournaments.single.games.single;
      log = saved.logs.single;
      score = const ScoringEngine().score(saved, log, const MatchRules());
      expect(score.homeRotation, 3);
      expect(score.homePoints, 1);
      expect(score.awayPoints, 1);
    },
  );

  test('quick libero swaps replace and restore the selected player', () async {
    const benchPlayer = Player(
      id: 'home-bench',
      number: 20,
      name: 'Bench Player',
      position: PlayerPosition.OH,
    );
    final libero = homeTeam.players.last;
    final trackedHome = homeTeam.copyWith(
      players: [...homeTeam.players, benchPlayer],
    );
    final game = Game(
      id: 'game',
      tournamentId: 'tournament',
      homeTeamId: trackedHome.id,
      awayTeamId: awayTeam.id,
      scheduledAt: DateTime.utc(2026, 10, 3),
      venue: 'Gym',
    );
    final tournament = Tournament(
      id: 'tournament',
      name: 'League',
      venue: 'Gym',
      startsOn: DateTime.utc(2026, 10, 3),
      endsOn: DateTime.utc(2026, 10, 3),
      createdAt: DateTime.utc(2026, 10, 1),
      teams: [trackedHome, awayTeam],
      games: [game],
    );
    final initial = AppData(deviceId: 'device', tournaments: [tournament]);
    final repository = MemoryAppRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appRepositoryProvider.overrideWithValue(repository),
        initialAppDataProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    await controller.startScorerLog(
      'tournament',
      'game',
      assignedTeamId: trackedHome.id,
      initialServingTeamId: trackedHome.id,
    );
    final regularPlayerIds = [
      ...homeTeam.players.take(5).map((player) => player.id),
      benchPlayer.id,
    ];
    await controller.setLineup(
      'tournament',
      'game',
      setNumber: 1,
      playerIds: regularPlayerIds,
    );

    final incomingLibero = await controller.recordLiberoSwap(
      'tournament',
      'game',
      selectedPlayerId: regularPlayerIds.first,
      liberoId: libero.id,
    );
    expect(incomingLibero, libero.id);
    var log =
        (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.serviceOrderFor(trackedHome.id, 1).first, libero.id);
    expect(log.substitutions.single.isLiberoReplacement, isTrue);

    final restoredPlayer = await controller.recordLiberoSwap(
      'tournament',
      'game',
      selectedPlayerId: libero.id,
      liberoId: libero.id,
    );
    expect(restoredPlayer, regularPlayerIds.first);
    log = (await repository.load()).tournaments.single.games.single.logs.single;
    expect(
      log.serviceOrderFor(trackedHome.id, 1).first,
      regularPlayerIds.first,
    );
    expect(log.substitutions, hasLength(2));
    expect(log.substitutions.every((item) => item.isLiberoReplacement), isTrue);

    await expectLater(
      controller.recordLiberoSwap(
        'tournament',
        'game',
        selectedPlayerId: regularPlayerIds[1],
        liberoId: libero.id,
      ),
      throwsStateError,
    );
    await controller.recordLiberoSwap(
      'tournament',
      'game',
      selectedPlayerId: regularPlayerIds[4],
      liberoId: libero.id,
    );
    await controller.awardRally(
      'tournament',
      'game',
      winnerTeamId: trackedHome.id,
      actions: const [],
    );
    log = (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.serviceOrderFor(trackedHome.id, 1)[4], libero.id);
    expect(log.substitutions, hasLength(3));

    await controller.awardRally(
      'tournament',
      'game',
      winnerTeamId: awayTeam.id,
      actions: const [],
    );
    await controller.awardRally(
      'tournament',
      'game',
      winnerTeamId: trackedHome.id,
      actions: const [],
    );
    log = (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.serviceOrderFor(trackedHome.id, 1)[4], regularPlayerIds[4]);
    expect(log.substitutions, hasLength(4));
    expect(log.substitutions.last.automaticAfterEventId, log.rallies.last.id);
    expect(
      Substitution.fromJson(log.substitutions.last.toJson())
          .automaticAfterEventId,
      log.rallies.last.id,
    );

    await controller.undoLastRally('tournament', 'game', 'Wrong point');
    log = (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.serviceOrderFor(trackedHome.id, 1)[4], libero.id);
    expect(log.substitutions, hasLength(3));
    await controller.awardRally(
      'tournament',
      'game',
      winnerTeamId: trackedHome.id,
      actions: const [],
    );
    await controller.recordLiberoSwap(
      'tournament',
      'game',
      selectedPlayerId: regularPlayerIds[5],
      liberoId: libero.id,
    );
    await controller.rotateLineupManually('tournament', 'game');
    log = (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.serviceOrderFor(trackedHome.id, 1)[5], regularPlayerIds[5]);
    expect(
      log.substitutions.last.automaticAfterEventId,
      log.rotationAdjustments.last.id,
    );

    await controller.recordLiberoSwap(
      'tournament',
      'game',
      selectedPlayerId: regularPlayerIds[1],
      liberoId: libero.id,
    );
    await controller.rotateLineupManually('tournament', 'game');
    log = (await repository.load()).tournaments.single.games.single.logs.single;
    expect(log.serviceOrderFor(trackedHome.id, 1)[1], libero.id);
    expect(log.substitutions.last.automaticAfterEventId, isNull);
  });

  test('links a separately created scorer log to a local game', () async {
    final now = DateTime.utc(2026, 10, 3);
    const sourceHome = TournamentTeam(
      id: 'source-home',
      name: 'Home Club',
      shortCode: 'HOM',
      colorValue: 0xFF123456,
    );
    const sourceAway = TournamentTeam(
      id: 'source-away',
      name: 'Away Club',
      shortCode: 'AWY',
      colorValue: 0xFF654321,
    );
    final sourceLog = ScorerLog(
      id: 'source-log',
      gameId: 'source-game',
      assignedTeamId: sourceAway.id,
      deviceId: 'other-device',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: sourceHome.id,
    );
    final sourceGame = Game(
      id: 'source-game',
      tournamentId: 'source-tournament',
      homeTeamId: sourceHome.id,
      awayTeamId: sourceAway.id,
      scheduledAt: now,
      venue: 'Gym',
      logs: [sourceLog],
    );
    final sourceTournament = Tournament(
      id: 'source-tournament',
      name: 'Separate Tournament',
      venue: 'Gym',
      startsOn: now,
      endsOn: now,
      createdAt: now,
      teams: const [sourceHome, sourceAway],
      games: [sourceGame],
    );
    final localLog = ScorerLog(
      id: 'local-log',
      gameId: 'target-game',
      assignedTeamId: homeTeam.id,
      deviceId: 'device',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: homeTeam.id,
    );
    final targetGame = Game(
      id: 'target-game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: now,
      venue: 'Gym',
      status: GameStatus.inProgress,
      logs: [localLog],
    );
    final targetTournament = testTournament(games: [targetGame]);
    final initial = AppData(
      deviceId: 'device',
      tournaments: [targetTournament],
    );
    final repository = MemoryAppRepository(initial);
    final container = ProviderContainer(
      overrides: [
        appRepositoryProvider.overrideWithValue(repository),
        initialAppDataProvider.overrideWithValue(initial),
      ],
    );
    addTearDown(container.dispose);
    final package = const PortablePackageService().createGamePackage(
      packageId: 'separate-package',
      deviceId: 'other-device',
      exportedAt: now,
      tournament: sourceTournament,
      game: sourceGame,
      log: sourceLog,
    );

    await container
        .read(appControllerProvider.notifier)
        .linkGamePackage(
          package,
          targetTournamentId: targetTournament.id,
          targetGameId: targetGame.id,
          sourceHomeMapsToTargetHome: true,
          playerIdMap: const {},
        );

    final linkedGame =
        (await repository.load()).tournaments.single.games.single;
    expect(linkedGame.status, GameStatus.awaitingReconciliation);
    expect(linkedGame.logs, hasLength(2));
    expect(linkedGame.logs.last.gameId, targetGame.id);
    expect(linkedGame.logs.last.assignedTeamId, awayTeam.id);
  });
}
