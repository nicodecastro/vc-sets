import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/game_linking.dart';
import '../domain/packages.dart';
import '../domain/reconciliation.dart';
import '../domain/scoring.dart';
import '../domain/sample_tournament.dart';
import '../domain/statistics.dart';
import 'providers.dart';

class AppController extends Notifier<AppData> {
  final _uuid = const Uuid();

  @override
  AppData build() => ref.watch(initialAppDataProvider);

  Future<void> _commit(AppData next) async {
    state = next;
    await ref.read(appRepositoryProvider).save(next);
  }

  Future<String> createTournament({
    required String name,
    required String venue,
    required DateTime startsOn,
    required DateTime endsOn,
  }) async {
    final tournament = Tournament(
      id: _uuid.v4(),
      name: name.trim(),
      venue: venue.trim(),
      startsOn: startsOn,
      endsOn: endsOn,
      createdAt: DateTime.now(),
    );
    await _commit(
      state.copyWith(tournaments: [...state.tournaments, tournament]),
    );
    return tournament.id;
  }

  Future<String> loadSampleTournament() async {
    if (state.tournaments.any((item) => item.id == sampleTournamentId)) {
      return sampleTournamentId;
    }
    await _commit(
      state.copyWith(
        tournaments: [...state.tournaments, buildSampleTournament()],
      ),
    );
    return sampleTournamentId;
  }

  Future<void> refreshSampleTournament() async {
    if (!state.tournaments.any((item) => item.id == sampleTournamentId)) {
      throw StateError('Sample tournament not found.');
    }
    await _commit(
      state.copyWith(
        tournaments: [
          for (final tournament in state.tournaments)
            tournament.id == sampleTournamentId
                ? buildSampleTournament()
                : tournament,
        ],
      ),
    );
  }

  Future<void> updateTournamentDetails(
    String tournamentId, {
    required String name,
    required String venue,
    required DateTime startsOn,
    required DateTime endsOn,
    required TournamentStatus status,
    TournamentFormat? format,
    int? poolCount,
    int? qualifiersPerPool,
    int? knockoutSize,
    bool? thirdPlaceEnabled,
    MatchRules? poolRules,
    MatchRules? semifinalRules,
    MatchRules? finalRules,
    MatchRules? thirdPlaceRules,
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw StateError('Tournament name is required.');
    }
    if (endsOn.isBefore(startsOn)) {
      throw StateError('The end date cannot be before the start date.');
    }
    await _updateTournament(tournamentId, (tournament) {
      final nextFormat = format ?? tournament.format;
      final nextPoolCount = poolCount ?? tournament.poolCount;
      final nextQualifiers = qualifiersPerPool ?? tournament.qualifiersPerPool;
      final nextKnockoutSize = knockoutSize ?? tournament.knockoutSize;
      if (![1, 2, 4].contains(nextPoolCount)) {
        throw StateError('Pool count must be 1, 2, or 4.');
      }
      if (nextQualifiers < 1) {
        throw StateError('At least one team must qualify from each pool.');
      }
      final qualifyingTeams = nextPoolCount * nextQualifiers;
      if (nextFormat == TournamentFormat.poolsThenKnockout &&
          ![2, 4, 8].contains(qualifyingTeams)) {
        throw StateError('The total number of qualifiers must be 2, 4, or 8.');
      }
      if (![2, 4, 8].contains(nextKnockoutSize)) {
        throw StateError('Knockout size must be 2, 4, or 8 teams.');
      }
      final hasBracketGames = tournament.games.any(
        (game) => game.stage == GameStage.bracket,
      );
      final nextThirdPlaceEnabled =
          thirdPlaceEnabled ?? tournament.thirdPlaceEnabled;
      if (hasBracketGames &&
          (nextFormat != tournament.format ||
              nextPoolCount != tournament.poolCount ||
              nextQualifiers != tournament.qualifiersPerPool ||
              nextKnockoutSize != tournament.knockoutSize)) {
        throw StateError(
          'Delete the existing knockout games before changing the tournament format.',
        );
      }
      final finalRoundGenerated = tournament.games.any(
        (game) =>
            game.stage == GameStage.bracket &&
            (game.bracketType == BracketGameType.finalMatch ||
                game.bracketType == BracketGameType.thirdPlace),
      );
      if (finalRoundGenerated &&
          nextThirdPlaceEnabled != tournament.thirdPlaceEnabled) {
        throw StateError(
          'Delete the generated final round before changing the third-place option.',
        );
      }
      final hasPoolGames = tournament.games.any(
        (game) => game.stage == GameStage.pool,
      );
      if (hasPoolGames &&
          (nextFormat != tournament.format ||
              nextPoolCount != tournament.poolCount)) {
        throw StateError(
          'Delete the existing pool games before changing the format or pool count.',
        );
      }
      var teams = tournament.teams;
      if (nextPoolCount != tournament.poolCount) {
        teams = [
          for (var index = 0; index < teams.length; index++)
            teams[index].copyWith(poolNumber: index % nextPoolCount + 1),
        ];
      }
      return tournament.copyWith(
        name: cleanName,
        venue: venue.trim(),
        startsOn: startsOn,
        endsOn: endsOn,
        status: status,
        format: nextFormat,
        poolCount: nextPoolCount,
        qualifiersPerPool: nextQualifiers,
        knockoutSize: nextKnockoutSize,
        thirdPlaceEnabled: nextThirdPlaceEnabled,
        poolRules: poolRules ?? tournament.poolRules,
        semifinalRules: semifinalRules ?? tournament.semifinalRules,
        finalRules: finalRules ?? tournament.finalRules,
        thirdPlaceRules: thirdPlaceRules ?? tournament.thirdPlaceRules,
        teams: teams,
      );
    });
  }

  Future<void> addTeam(
    String tournamentId,
    String name,
    String shortCode,
    int colorValue,
  ) async {
    await _updateTournament(tournamentId, (tournament) {
      final team = TournamentTeam(
        id: _uuid.v4(),
        name: name.trim(),
        shortCode: shortCode.trim().toUpperCase(),
        colorValue: colorValue,
        poolNumber: tournament.format == TournamentFormat.poolsThenKnockout
            ? tournament.teams.length % tournament.poolCount + 1
            : 1,
      );
      if (tournament.teams.any(
        (item) => item.name.toLowerCase() == team.name.toLowerCase(),
      )) {
        throw StateError('A team with that name already exists.');
      }
      return tournament.copyWith(teams: [...tournament.teams, team]);
    });
  }

  Future<void> updateTeamDetails(
    String tournamentId,
    String teamId, {
    required String name,
    required String shortCode,
    int? poolNumber,
  }) async {
    final cleanName = name.trim();
    final cleanCode = shortCode.trim().toUpperCase();
    if (cleanName.isEmpty) throw StateError('Team name is required.');
    if (cleanCode.isEmpty || cleanCode.length > 4) {
      throw StateError('Short code must contain one to four characters.');
    }
    await _updateTournament(tournamentId, (tournament) {
      final currentTeam = tournament.team(teamId);
      if (poolNumber != null &&
          poolNumber != currentTeam.poolNumber &&
          tournament.games.any((game) => game.stage == GameStage.pool)) {
        throw StateError(
          'Delete the existing pool games before moving a team to another pool.',
        );
      }
      if (poolNumber != null &&
          (poolNumber < 1 || poolNumber > tournament.poolCount)) {
        throw StateError('Choose a valid tournament pool.');
      }
      if (tournament.teams.any(
        (team) =>
            team.id != teamId &&
            team.name.toLowerCase() == cleanName.toLowerCase(),
      )) {
        throw StateError('Another team already uses that name.');
      }
      if (tournament.teams.any(
        (team) =>
            team.id != teamId &&
            team.shortCode.toLowerCase() == cleanCode.toLowerCase(),
      )) {
        throw StateError('Another team already uses that short code.');
      }
      final teams = tournament.teams.map((team) {
        if (team.id != teamId) return team;
        return TournamentTeam(
          id: team.id,
          name: cleanName,
          shortCode: cleanCode,
          colorValue: team.colorValue,
          poolNumber: poolNumber ?? team.poolNumber,
          players: team.players,
        );
      }).toList();
      return tournament.copyWith(teams: teams);
    });
  }

  Future<void> reorderTeams(
    String tournamentId,
    int oldIndex,
    int newIndex,
  ) async {
    await _updateTournament(tournamentId, (tournament) {
      if (oldIndex < 0 ||
          oldIndex >= tournament.teams.length ||
          newIndex < 0 ||
          newIndex >= tournament.teams.length) {
        throw StateError('Invalid team order.');
      }
      final teams = [...tournament.teams];
      teams.insert(newIndex, teams.removeAt(oldIndex));
      return tournament.copyWith(teams: teams);
    });
  }

  Future<void> updateBracketSettings(
    String tournamentId, {
    required bool enabled,
    required int size,
  }) async {
    if (![2, 4, 8].contains(size)) {
      throw StateError('Bracket size must be 2, 4, or 8 teams.');
    }
    await _updateTournament(tournamentId, (tournament) {
      final hasBracketGames = tournament.games.any(
        (game) => game.stage == GameStage.bracket,
      );
      if (hasBracketGames && (!enabled || size != tournament.bracketSize)) {
        throw StateError(
          'Delete the existing bracket games before changing bracket settings.',
        );
      }
      return tournament.copyWith(
        format: enabled
            ? TournamentFormat.poolsThenKnockout
            : TournamentFormat.roundRobin,
        poolCount: 1,
        qualifiersPerPool: size,
        knockoutSize: size,
      );
    });
  }

  Future<void> addPlayer(
    String tournamentId,
    String teamId, {
    required int number,
    required String name,
    required PlayerPosition position,
    bool isCaptain = false,
  }) async {
    await _updateTournament(tournamentId, (tournament) {
      final teams = tournament.teams.map((team) {
        if (team.id != teamId) return team;
        if (team.players.any((player) => player.number == number)) {
          throw StateError('Jersey number $number is already assigned.');
        }
        final player = Player(
          id: _uuid.v4(),
          number: number,
          name: name.trim(),
          position: position,
          isCaptain: isCaptain,
        );
        return team.copyWith(players: [...team.players, player]);
      }).toList();
      return tournament.copyWith(teams: teams);
    });
  }

  Future<void> replaceTeamRoster(
    String tournamentId,
    String teamId,
    List<Player> players,
  ) async {
    final numbers = <int>{};
    final ids = <String>{};
    for (final player in players) {
      if (player.name.trim().isEmpty) {
        throw StateError('Every player must have a name.');
      }
      if (player.number < 0) {
        throw StateError('Jersey numbers cannot be negative.');
      }
      if (!numbers.add(player.number)) {
        throw StateError(
          'Jersey number ${player.number} is assigned more than once.',
        );
      }
      if (!ids.add(player.id)) {
        throw StateError('The roster contains a duplicate player record.');
      }
    }
    if (players.where((player) => player.isCaptain).length > 1) {
      throw StateError('Only one captain can be selected.');
    }

    await _updateTournament(tournamentId, (tournament) {
      final teamIndex = tournament.teams.indexWhere(
        (team) => team.id == teamId,
      );
      if (teamIndex < 0) throw StateError('Team not found.');
      final referencedPlayerIds = <String>{};
      for (final game in tournament.games) {
        final logs = <ScorerLog>[
          ...game.logs,
          if (game.officialLog != null) game.officialLog!,
        ];
        for (final log in logs) {
          for (final lineup in log.lineups.where(
            (item) => item.teamId == teamId,
          )) {
            referencedPlayerIds.addAll(lineup.playerIds);
          }
          for (final substitution in log.substitutions.where(
            (item) => item.teamId == teamId,
          )) {
            referencedPlayerIds
              ..add(substitution.playerOutId)
              ..add(substitution.playerInId);
          }
          for (final action in log.rallies.expand((rally) => rally.actions)) {
            if (action.teamId == teamId && action.playerId != null) {
              referencedPlayerIds.add(action.playerId!);
            }
          }
        }
      }
      final removedReferenced = referencedPlayerIds.difference(ids);
      if (removedReferenced.isNotEmpty) {
        throw StateError(
          'Players already referenced by a scorer log cannot be removed. Edit their details instead.',
        );
      }
      final teams = [...tournament.teams];
      teams[teamIndex] = teams[teamIndex].copyWith(players: players);
      return tournament.copyWith(teams: teams);
    });
  }

  Future<void> generateRoundRobin(
    String tournamentId, {
    DateTime? firstGameAt,
  }) async {
    await _updateTournament(tournamentId, (tournament) {
      if (tournament.format == TournamentFormat.knockoutOnly) {
        throw StateError('This tournament is configured as knockout only.');
      }
      if (tournament.teams.length < 2) {
        throw StateError('Add at least two teams first.');
      }
      if (tournament.format == TournamentFormat.poolsThenKnockout) {
        for (var pool = 1; pool <= tournament.poolCount; pool++) {
          final count = tournament.teams
              .where((team) => team.poolNumber == pool)
              .length;
          if (count < 2 || count < tournament.qualifiersPerPool) {
            throw StateError(
              'Pool ${_poolLabel(pool)} needs at least ${tournament.qualifiersPerPool.clamp(2, 99)} teams.',
            );
          }
        }
      }
      final existingPairs = tournament.games
          .where((game) => game.stage == GameStage.pool)
          .map((game) => {game.homeTeamId, game.awayTeamId}.toList()..sort())
          .map((pair) => pair.join(':'))
          .toSet();
      final games = [...tournament.games];
      var slot =
          firstGameAt ?? tournament.startsOn.add(const Duration(hours: 9));
      for (var home = 0; home < tournament.teams.length; home++) {
        for (var away = home + 1; away < tournament.teams.length; away++) {
          final homeTeam = tournament.teams[home];
          final awayTeam = tournament.teams[away];
          if (tournament.format == TournamentFormat.poolsThenKnockout &&
              homeTeam.poolNumber != awayTeam.poolNumber) {
            continue;
          }
          final pair = [tournament.teams[home].id, tournament.teams[away].id]
            ..sort();
          if (existingPairs.contains(pair.join(':'))) continue;
          games.add(
            Game(
              id: _uuid.v4(),
              tournamentId: tournament.id,
              homeTeamId: tournament.teams[home].id,
              awayTeamId: tournament.teams[away].id,
              scheduledAt: slot,
              venue: tournament.venue,
              poolNumber:
                  tournament.format == TournamentFormat.poolsThenKnockout
                  ? homeTeam.poolNumber
                  : 1,
              rulesSnapshot: tournament.effectivePoolRules,
            ),
          );
          slot = slot.add(const Duration(hours: 2));
        }
      }
      return tournament.copyWith(status: TournamentStatus.active, games: games);
    });
  }

  Future<void> generateBracket(String tournamentId) async {
    await _updateTournament(tournamentId, (tournament) {
      if (tournament.format == TournamentFormat.roundRobin) {
        throw StateError('Choose a tournament format with a knockout phase.');
      }
      if (tournament.teams.length < tournament.bracketSize) {
        throw StateError(
          'This tournament does not have enough teams for the selected bracket size.',
        );
      }
      if (tournament.games.any((game) => game.stage == GameStage.bracket)) {
        throw StateError('A bracket has already been generated.');
      }
      final poolGames = tournament.games
          .where((game) => game.stage == GameStage.pool)
          .toList();
      late final List<TournamentTeam> qualifiers;
      if (tournament.format == TournamentFormat.poolsThenKnockout) {
        if (poolGames.isEmpty ||
            poolGames.any((game) => game.status != GameStatus.finalized)) {
          throw StateError(
            'Finalize every pool game before generating the knockout phase.',
          );
        }
        qualifiers = [];
        final poolRows = <int, List<StandingRow>>{};
        for (var pool = 1; pool <= tournament.poolCount; pool++) {
          final rows = const StatisticsService().standings(
            tournament,
            poolNumber: pool,
          );
          if (rows.length < tournament.qualifiersPerPool) {
            throw StateError(
              'Pool ${_poolLabel(pool)} does not have enough teams.',
            );
          }
          poolRows[pool] = rows;
        }
        for (var rank = 0; rank < tournament.qualifiersPerPool; rank++) {
          for (var pool = 1; pool <= tournament.poolCount; pool++) {
            qualifiers.add(poolRows[pool]![rank].team);
          }
        }
      } else {
        qualifiers = tournament.teams.take(tournament.knockoutSize).toList();
      }
      final seedOrder = _bracketSeedOrder(tournament.bracketSize);
      var scheduledAt = poolGames.isEmpty
          ? tournament.startsOn.add(const Duration(hours: 9))
          : poolGames
                .map((game) => game.scheduledAt)
                .reduce((a, b) => a.isAfter(b) ? a : b)
                .add(const Duration(hours: 2));
      final games = [...tournament.games];
      final firstRoundType = tournament.bracketSize == 2
          ? BracketGameType.finalMatch
          : BracketGameType.standard;
      final firstRoundRules = tournament.bracketSize == 2
          ? tournament.effectiveFinalRules
          : tournament.effectiveSemifinalRules;
      for (var index = 0; index < seedOrder.length; index += 2) {
        games.add(
          Game(
            id: _uuid.v4(),
            tournamentId: tournament.id,
            homeTeamId: qualifiers[seedOrder[index] - 1].id,
            awayTeamId: qualifiers[seedOrder[index + 1] - 1].id,
            scheduledAt: scheduledAt,
            venue: tournament.venue,
            stage: GameStage.bracket,
            bracketRound: 1,
            bracketOrder: index ~/ 2,
            bracketType: firstRoundType,
            rulesSnapshot: firstRoundRules,
          ),
        );
        scheduledAt = scheduledAt.add(const Duration(hours: 2));
      }
      return tournament.copyWith(games: games);
    });
  }

  Future<void> advanceBracket(String tournamentId) async {
    await _updateTournament(tournamentId, (tournament) {
      final bracketGames = tournament.games
          .where(
            (game) =>
                game.stage == GameStage.bracket &&
                game.bracketType != BracketGameType.thirdPlace,
          )
          .toList();
      if (bracketGames.isEmpty) throw StateError('Generate the bracket first.');
      final currentRound = bracketGames
          .map((game) => game.bracketRound ?? 1)
          .reduce((a, b) => a > b ? a : b);
      final currentGames =
          bracketGames
              .where((game) => game.bracketRound == currentRound)
              .toList()
            ..sort(
              (a, b) => (a.bracketOrder ?? 0).compareTo(b.bracketOrder ?? 0),
            );
      if (currentGames.length == 1) {
        throw StateError('The bracket is already complete.');
      }
      if (currentGames.any(
        (game) =>
            game.status != GameStatus.finalized || game.officialLog == null,
      )) {
        throw StateError(
          'Finalize every game in the current bracket round first.',
        );
      }
      final nextRound = currentRound + 1;
      if (bracketGames.any((game) => game.bracketRound == nextRound)) {
        throw StateError('The next bracket round has already been generated.');
      }
      final winners = currentGames
          .map((game) => _gameWinner(game, tournament.rulesFor(game)))
          .toList();
      final losers = currentGames
          .map((game) => _gameLoser(game, tournament.rulesFor(game)))
          .toList();
      var scheduledAt = currentGames
          .map((game) => game.scheduledAt)
          .reduce((a, b) => a.isAfter(b) ? a : b)
          .add(const Duration(hours: 2));
      final games = [...tournament.games];
      if (winners.length == 2 && tournament.thirdPlaceEnabled) {
        games.add(
          Game(
            id: _uuid.v4(),
            tournamentId: tournament.id,
            homeTeamId: losers[0],
            awayTeamId: losers[1],
            scheduledAt: scheduledAt,
            venue: tournament.venue,
            stage: GameStage.bracket,
            bracketRound: nextRound,
            bracketOrder: 1,
            bracketType: BracketGameType.thirdPlace,
            rulesSnapshot: tournament.effectiveThirdPlaceRules,
          ),
        );
        scheduledAt = scheduledAt.add(const Duration(hours: 2));
      }
      for (var index = 0; index < winners.length; index += 2) {
        final isFinal = winners.length == 2;
        games.add(
          Game(
            id: _uuid.v4(),
            tournamentId: tournament.id,
            homeTeamId: winners[index],
            awayTeamId: winners[index + 1],
            scheduledAt: scheduledAt,
            venue: tournament.venue,
            stage: GameStage.bracket,
            bracketRound: nextRound,
            bracketOrder: index ~/ 2,
            bracketType: isFinal
                ? BracketGameType.finalMatch
                : BracketGameType.standard,
            rulesSnapshot: isFinal
                ? tournament.effectiveFinalRules
                : tournament.effectiveSemifinalRules,
          ),
        );
        scheduledAt = scheduledAt.add(const Duration(hours: 2));
      }
      return tournament.copyWith(games: games);
    });
  }

  List<int> _bracketSeedOrder(int size) {
    var seeds = <int>[1, 2];
    while (seeds.length < size) {
      final sum = seeds.length * 2 + 1;
      seeds = [
        for (final seed in seeds) ...[seed, sum - seed],
      ];
    }
    return seeds;
  }

  String _gameWinner(Game game, MatchRules rules) {
    final official = game.officialLog;
    if (official == null) {
      throw StateError('A bracket game has no official result.');
    }
    final score = const ScoringEngine().score(game, official, rules);
    return score.homeSets > score.awaySets ? game.homeTeamId : game.awayTeamId;
  }

  String _gameLoser(Game game, MatchRules rules) {
    final winner = _gameWinner(game, rules);
    return winner == game.homeTeamId ? game.awayTeamId : game.homeTeamId;
  }

  String _poolLabel(int poolNumber) =>
      String.fromCharCode('A'.codeUnitAt(0) + poolNumber - 1);

  Future<void> addGame(
    String tournamentId, {
    required String homeTeamId,
    required String awayTeamId,
    required DateTime scheduledAt,
    required String venue,
  }) async {
    if (homeTeamId == awayTeamId) {
      throw StateError('Choose two different teams.');
    }
    await _updateTournament(tournamentId, (tournament) {
      if (tournament.format == TournamentFormat.knockoutOnly) {
        throw StateError(
          'Generate the configured knockout bracket instead of adding a pool game.',
        );
      }
      final home = tournament.team(homeTeamId);
      final away = tournament.team(awayTeamId);
      if (tournament.format == TournamentFormat.poolsThenKnockout &&
          home.poolNumber != away.poolNumber) {
        throw StateError('Pool games must use teams from the same pool.');
      }
      return tournament.copyWith(
        status: TournamentStatus.active,
        games: [
          ...tournament.games,
          Game(
            id: _uuid.v4(),
            tournamentId: tournamentId,
            homeTeamId: homeTeamId,
            awayTeamId: awayTeamId,
            scheduledAt: scheduledAt,
            venue: venue,
            poolNumber: tournament.format == TournamentFormat.poolsThenKnockout
                ? home.poolNumber
                : 1,
            rulesSnapshot: tournament.effectivePoolRules,
          ),
        ],
      );
    });
  }

  Future<void> updateRules(String tournamentId, MatchRules rules) async {
    if (rules.setsToWin < 1 ||
        rules.regularSetTarget < 1 ||
        rules.decidingSetTarget < 1 ||
        rules.winBy < 1) {
      throw StateError('Scoring values must be positive.');
    }
    await _updateTournament(
      tournamentId,
      (tournament) => tournament.copyWith(
        rules: rules,
        poolRules: _applyMatchLength(rules, tournament.effectivePoolRules),
        semifinalRules: _applyMatchLength(
          rules,
          tournament.effectiveSemifinalRules,
        ),
        finalRules: _applyMatchLength(rules, tournament.effectiveFinalRules),
        thirdPlaceRules: _applyMatchLength(
          rules,
          tournament.effectiveThirdPlaceRules,
        ),
      ),
    );
  }

  MatchRules _applyMatchLength(MatchRules base, MatchRules format) =>
      base.copyWith(setsToWin: format.setsToWin, maxSets: format.maxSets);

  Future<void> startScorerLog(
    String tournamentId,
    String gameId, {
    required String assignedTeamId,
    required String initialServingTeamId,
  }) async {
    await _updateGame(tournamentId, gameId, (tournament, game) {
      if (game.logs.any((log) => log.deviceId == state.deviceId)) return game;
      final now = DateTime.now();
      final log = ScorerLog(
        id: _uuid.v4(),
        gameId: game.id,
        assignedTeamId: assignedTeamId,
        deviceId: state.deviceId,
        createdAt: now,
        updatedAt: now,
        initialServingTeamId: initialServingTeamId,
      );
      return game.copyWith(
        status: GameStatus.inProgress,
        logs: [...game.logs, log],
      );
    });
  }

  Future<void> setLineup(
    String tournamentId,
    String gameId, {
    required int setNumber,
    required List<String> playerIds,
  }) async {
    await _updateGame(tournamentId, gameId, (tournament, game) {
      final index = game.logs.indexWhere(
        (log) => log.deviceId == state.deviceId,
      );
      if (index < 0) {
        throw StateError('Start a scorer log on this device first.');
      }
      final log = game.logs[index];
      final team = tournament.team(log.assignedTeamId);
      final errors = const ScoringEngine().validateStartingLineup(
        team,
        playerIds,
      );
      if (errors.isNotEmpty) throw StateError(errors.join(' '));
      final now = DateTime.now();
      final logs = [...game.logs];
      logs[index] = log.copyWith(
        updatedAt: now,
        lineups: [
          ...log.lineups,
          LineupSnapshot(
            teamId: team.id,
            playerIds: playerIds,
            setNumber: setNumber,
            recordedAt: now,
          ),
        ],
      );
      return game.copyWith(logs: logs);
    });
  }

  Future<void> recordSubstitution(
    String tournamentId,
    String gameId, {
    required String playerOutId,
    required String playerInId,
  }) async {
    if (playerOutId == playerInId) {
      throw StateError('Choose two different players.');
    }
    await _updateGame(tournamentId, gameId, (tournament, game) {
      final index = game.logs.indexWhere(
        (log) => log.deviceId == state.deviceId,
      );
      if (index < 0) {
        throw StateError('Start a scorer log on this device first.');
      }
      final log = game.logs[index];
      final score = const ScoringEngine().score(
        game,
        log,
        tournament.rulesFor(game),
      );
      if (score.isComplete) throw StateError('The match is already complete.');
      final team = tournament.team(log.assignedTeamId);
      final serviceOrder = log.serviceOrderFor(team.id, score.setNumber);
      if (!serviceOrder.contains(playerOutId)) {
        throw StateError('The outgoing player is not currently on court.');
      }
      if (!team.players.any((player) => player.id == playerInId)) {
        throw StateError(
          'The incoming player is not on the tournament roster.',
        );
      }
      if (serviceOrder.contains(playerInId)) {
        throw StateError('The incoming player is already on court.');
      }
      final now = DateTime.now();
      final logs = [...game.logs];
      logs[index] = log.copyWith(
        updatedAt: now,
        substitutions: [
          ...log.substitutions,
          Substitution(
            id: _uuid.v4(),
            teamId: team.id,
            setNumber: score.setNumber,
            playerOutId: playerOutId,
            playerInId: playerInId,
            homeScore: score.homePoints,
            awayScore: score.awayPoints,
            recordedAt: now,
          ),
        ],
      );
      return game.copyWith(logs: logs);
    });
  }

  Future<String> recordLiberoSwap(
    String tournamentId,
    String gameId, {
    required String selectedPlayerId,
    required String liberoId,
  }) async {
    String? incomingPlayerId;
    await _updateGame(tournamentId, gameId, (tournament, game) {
      final index = game.logs.indexWhere(
        (log) => log.deviceId == state.deviceId,
      );
      if (index < 0) {
        throw StateError('Start a scorer log on this device first.');
      }
      final log = game.logs[index];
      final score = const ScoringEngine().score(
        game,
        log,
        tournament.rulesFor(game),
      );
      if (score.isComplete) throw StateError('The match is already complete.');
      final team = tournament.team(log.assignedTeamId);
      final liberoMatches = team.players.where(
        (player) => player.id == liberoId && player.isLibero,
      );
      if (liberoMatches.isEmpty) {
        throw StateError('Select a libero from the tournament roster.');
      }
      final serviceOrder = log.serviceOrderFor(team.id, score.setNumber);
      if (!serviceOrder.contains(selectedPlayerId)) {
        throw StateError('Select an on-court player to swap.');
      }

      late final String outgoing;
      if (serviceOrder.contains(liberoId)) {
        if (selectedPlayerId != liberoId) {
          throw StateError(
            'Select the on-court libero to restore the replaced player.',
          );
        }
        final replacements = log.substitutions
            .where(
              (item) =>
                  item.teamId == team.id &&
                  item.setNumber == score.setNumber &&
                  item.isLiberoReplacement &&
                  item.playerInId == liberoId &&
                  !serviceOrder.contains(item.playerOutId),
            )
            .toList()
            .reversed;
        if (replacements.isEmpty) {
          throw StateError('There is no recorded player to restore.');
        }
        outgoing = liberoId;
        incomingPlayerId = replacements.first.playerOutId;
      } else {
        final court = log.courtOrderFor(
          team.id,
          score.setNumber,
          team.id == game.homeTeamId ? score.homeRotation : score.awayRotation,
        );
        if (court.length != 6 ||
            ![court[0], court[4], court[5]].contains(selectedPlayerId)) {
          throw StateError('A libero can replace only a back-row player.');
        }
        outgoing = selectedPlayerId;
        incomingPlayerId = liberoId;
      }

      final now = DateTime.now();
      final logs = [...game.logs];
      logs[index] = log.copyWith(
        updatedAt: now,
        substitutions: [
          ...log.substitutions,
          Substitution(
            id: _uuid.v4(),
            teamId: team.id,
            setNumber: score.setNumber,
            playerOutId: outgoing,
            playerInId: incomingPlayerId!,
            homeScore: score.homePoints,
            awayScore: score.awayPoints,
            recordedAt: now,
            kind: SubstitutionKind.liberoReplacement,
          ),
        ],
      );
      return game.copyWith(logs: logs);
    });
    return incomingPlayerId!;
  }

  Future<void> rotateLineupManually(String tournamentId, String gameId) async {
    await _updateGame(tournamentId, gameId, (tournament, game) {
      final index = game.logs.indexWhere(
        (log) => log.deviceId == state.deviceId,
      );
      if (index < 0) {
        throw StateError('Start a scorer log on this device first.');
      }
      final log = game.logs[index];
      final score = const ScoringEngine().score(
        game,
        log,
        tournament.rulesFor(game),
      );
      if (score.isComplete) throw StateError('The match is already complete.');
      if (log.lineupFor(log.assignedTeamId, score.setNumber) == null) {
        throw StateError('Save the R-5 lineup for this set first.');
      }
      final currentRotation = log.assignedTeamId == game.homeTeamId
          ? score.homeRotation
          : score.awayRotation;
      final now = DateTime.now();
      final logs = [...game.logs];
      final adjustment = RotationAdjustment(
        id: _uuid.v4(),
        teamId: log.assignedTeamId,
        setNumber: score.setNumber,
        afterRallySequence: log.rallies
            .where((rally) => rally.setNumber == score.setNumber)
            .length,
        rotation: currentRotation % 6 + 1,
        recordedAt: now,
      );
      final rotatedLog = log.copyWith(
        updatedAt: now,
        rotationAdjustments: [...log.rotationAdjustments, adjustment],
      );
      final rotatedScore = const ScoringEngine().score(
        game,
        rotatedLog,
        tournament.rulesFor(game),
      );
      logs[index] = _restoreFrontRowLibero(
        tournament,
        game,
        rotatedLog,
        rotatedScore,
        adjustment.id,
      );
      return game.copyWith(logs: logs);
    });
  }

  ScorerLog _restoreFrontRowLibero(
    Tournament tournament,
    Game game,
    ScorerLog log,
    MatchScore score,
    String triggerEventId,
  ) {
    if (score.isComplete) return log;
    final team = tournament.team(log.assignedTeamId);
    final rotation = team.id == game.homeTeamId
        ? score.homeRotation
        : score.awayRotation;
    final court = log.courtOrderFor(team.id, score.setNumber, rotation);
    if (court.length != 6) return log;
    final frontRow = court.sublist(1, 4);
    final liberos = team.players.where(
      (player) => player.isLibero && frontRow.contains(player.id),
    );
    if (liberos.isEmpty) return log;
    final libero = liberos.first;
    final serviceOrder = log.serviceOrderFor(team.id, score.setNumber);
    final replacements = log.substitutions
        .where(
          (item) =>
              item.teamId == team.id &&
              item.setNumber == score.setNumber &&
              item.isLiberoReplacement &&
              item.playerInId == libero.id &&
              !serviceOrder.contains(item.playerOutId),
        )
        .toList()
        .reversed;
    if (replacements.isEmpty) return log;
    final now = DateTime.now();
    return log.copyWith(
      updatedAt: now,
      substitutions: [
        ...log.substitutions,
        Substitution(
          id: _uuid.v4(),
          teamId: team.id,
          setNumber: score.setNumber,
          playerOutId: libero.id,
          playerInId: replacements.first.playerOutId,
          homeScore: score.homePoints,
          awayScore: score.awayPoints,
          recordedAt: now,
          kind: SubstitutionKind.liberoReplacement,
          automaticAfterEventId: triggerEventId,
        ),
      ],
    );
  }

  Future<void> recordTimeout(String tournamentId, String gameId) async {
    await _updateGame(tournamentId, gameId, (tournament, game) {
      final index = game.logs.indexWhere(
        (log) => log.deviceId == state.deviceId,
      );
      if (index < 0) {
        throw StateError('Start a scorer log on this device first.');
      }
      final log = game.logs[index];
      final score = const ScoringEngine().score(
        game,
        log,
        tournament.rulesFor(game),
      );
      if (score.isComplete) throw StateError('The match is already complete.');
      if (log.lineupFor(log.assignedTeamId, score.setNumber) == null) {
        throw StateError('Save the R-5 lineup for this set first.');
      }
      final used = log.timeouts
          .where(
            (timeout) =>
                timeout.teamId == log.assignedTeamId &&
                timeout.setNumber == score.setNumber,
          )
          .length;
      if (used >= 2) {
        throw StateError('This team has already used two timeouts this set.');
      }
      final now = DateTime.now();
      final logs = [...game.logs];
      logs[index] = log.copyWith(
        updatedAt: now,
        timeouts: [
          ...log.timeouts,
          TeamTimeout(
            id: _uuid.v4(),
            teamId: log.assignedTeamId,
            setNumber: score.setNumber,
            homeScore: score.homePoints,
            awayScore: score.awayPoints,
            recordedAt: now,
          ),
        ],
      );
      return game.copyWith(logs: logs);
    });
  }

  Future<void> awardRally(
    String tournamentId,
    String gameId, {
    required String winnerTeamId,
    required List<TeamAction> actions,
    String? overrideReason,
  }) async {
    await _updateGame(tournamentId, gameId, (tournament, game) {
      final index = game.logs.indexWhere(
        (log) => log.deviceId == state.deviceId,
      );
      if (index < 0) {
        throw StateError('Start a scorer log on this device first.');
      }
      final log = game.logs[index];
      if (actions.any((action) => action.teamId != log.assignedTeamId)) {
        throw StateError(
          'This device can record player actions only for its assigned team.',
        );
      }
      final before = const ScoringEngine().score(
        game,
        log,
        tournament.rulesFor(game),
      );
      final currentSet = before.setNumber;
      if (log.lineupFor(log.assignedTeamId, currentSet) == null) {
        throw StateError('Save the R-5 lineup for this set first.');
      }
      final rally = const ScoringEngine().nextRally(
        id: _uuid.v4(),
        game: game,
        log: log,
        rules: tournament.rulesFor(game),
        winnerTeamId: winnerTeamId,
        recordedAt: DateTime.now(),
        actions: actions,
        overrideReason: overrideReason,
      );
      final logs = [...game.logs];
      var updatedLog = log.copyWith(
        updatedAt: DateTime.now(),
        rallies: [...log.rallies, rally],
      );
      final score = const ScoringEngine().score(
        game,
        updatedLog,
        tournament.rulesFor(game),
      );
      final previousRotation = log.assignedTeamId == game.homeTeamId
          ? before.homeRotation
          : before.awayRotation;
      final currentRotation = log.assignedTeamId == game.homeTeamId
          ? rally.homeRotation
          : rally.awayRotation;
      if (score.setNumber == rally.setNumber &&
          currentRotation != previousRotation) {
        updatedLog = _restoreFrontRowLibero(
          tournament,
          game,
          updatedLog,
          score,
          rally.id,
        );
      }
      logs[index] = updatedLog;
      return game.copyWith(
        status: score.isComplete
            ? GameStatus.awaitingReconciliation
            : GameStatus.inProgress,
        logs: logs,
      );
    });
  }

  Future<void> undoLastRally(
    String tournamentId,
    String gameId,
    String reason,
  ) async {
    await _updateGame(tournamentId, gameId, (tournament, game) {
      final index = game.logs.indexWhere(
        (log) => log.deviceId == state.deviceId,
      );
      if (index < 0 || game.logs[index].rallies.isEmpty) return game;
      final log = game.logs[index];
      final removed = log.rallies.last;
      final logs = [...game.logs];
      logs[index] = log.copyWith(
        updatedAt: DateTime.now(),
        rallies: log.rallies.sublist(0, log.rallies.length - 1),
        substitutions: log.substitutions
            .where((item) => item.automaticAfterEventId != removed.id)
            .toList(),
        corrections: [
          ...log.corrections,
          Correction(
            id: _uuid.v4(),
            rallyId: removed.id,
            reason: reason,
            correctedAt: DateTime.now(),
            kind: 'undo',
          ),
        ],
      );
      return game.copyWith(status: GameStatus.inProgress, logs: logs);
    });
  }

  Future<void> importGamePackage(GamePackage package) async {
    if (state.importedPackageIds.contains(package.manifest.packageId)) {
      throw StateError('This package has already been imported.');
    }
    final tournaments = [...state.tournaments];
    final tournamentIndex = tournaments.indexWhere(
      (item) => item.id == package.tournament.id,
    );
    if (tournamentIndex < 0) {
      tournaments.add(
        package.tournament.copyWith(
          games: package.tournament.games
              .map(
                (game) => package.log == null
                    ? game
                    : game.copyWith(
                        logs: [package.log!],
                        status: GameStatus.inProgress,
                      ),
              )
              .toList(),
        ),
      );
    } else {
      final local = tournaments[tournamentIndex];
      final incomingGame = package.tournament.games.firstWhere(
        (game) => game.id == package.gameId,
      );
      final games = [...local.games];
      final gameIndex = games.indexWhere((game) => game.id == package.gameId);
      if (gameIndex < 0) {
        games.add(
          package.log == null
              ? incomingGame
              : incomingGame.copyWith(
                  logs: [package.log!],
                  status: GameStatus.inProgress,
                ),
        );
      } else if (package.log != null) {
        final current = games[gameIndex];
        if (current.logs.any((log) => log.id == package.log!.id)) {
          throw StateError('This scorer log is already attached to the game.');
        }
        games[gameIndex] = current.copyWith(
          status: GameStatus.awaitingReconciliation,
          logs: [...current.logs, package.log!],
        );
      }
      tournaments[tournamentIndex] = local.copyWith(games: games);
    }
    await _commit(
      state.copyWith(
        tournaments: tournaments,
        importedPackageIds: [
          ...state.importedPackageIds,
          package.manifest.packageId,
        ],
      ),
    );
  }

  Future<void> linkGamePackage(
    GamePackage package, {
    required String targetTournamentId,
    required String targetGameId,
    required bool sourceHomeMapsToTargetHome,
    required Map<String, String?> playerIdMap,
  }) async {
    final sourceLog = package.log;
    if (sourceLog == null) {
      throw StateError('This package does not contain a scorer log to link.');
    }
    final linkImportId =
        'link:${package.manifest.packageId}:$targetTournamentId:$targetGameId';
    if (state.importedPackageIds.contains(linkImportId)) {
      throw StateError('This package is already linked to the selected game.');
    }
    final sourceGame = package.tournament.games.firstWhere(
      (game) => game.id == package.gameId,
      orElse: () => throw StateError('The package game is missing.'),
    );
    final tournaments = [...state.tournaments];
    final tournamentIndex = tournaments.indexWhere(
      (item) => item.id == targetTournamentId,
    );
    if (tournamentIndex < 0) throw StateError('Target tournament not found.');
    final targetTournament = tournaments[tournamentIndex];
    final games = [...targetTournament.games];
    final gameIndex = games.indexWhere((game) => game.id == targetGameId);
    if (gameIndex < 0) throw StateError('Target game not found.');
    final targetGame = games[gameIndex];
    if (targetGame.status == GameStatus.finalized) {
      throw StateError(
        'Reopen the finalized target game before linking a log.',
      );
    }
    final linkedLog = const GameLinkingService().linkLog(
      sourceTournament: package.tournament,
      sourceGame: sourceGame,
      sourceLog: sourceLog,
      targetTournament: targetTournament,
      targetGame: targetGame,
      sourceHomeMapsToTargetHome: sourceHomeMapsToTargetHome,
      playerIdMap: playerIdMap,
      linkedLogId: _uuid.v4(),
    );
    games[gameIndex] = targetGame.copyWith(
      status: targetGame.logs.isEmpty
          ? GameStatus.inProgress
          : GameStatus.awaitingReconciliation,
      logs: [...targetGame.logs, linkedLog],
    );
    tournaments[tournamentIndex] = targetTournament.copyWith(games: games);
    await _commit(
      state.copyWith(
        tournaments: tournaments,
        importedPackageIds: [...state.importedPackageIds, linkImportId],
      ),
    );
  }

  Future<void> finalizeReconciliation(
    String tournamentId,
    String gameId, {
    required Set<String> preferImported,
    required String reason,
    Map<String, Rally> rallyOverrides = const {},
    Map<String, Map<int, int>> setMappings = const {},
    Map<String, List<String>> excludedRallyIds = const {},
    Map<int, int>? setTargets,
  }) async {
    await _updateGame(tournamentId, gameId, (tournament, game) {
      if (game.logs.length < 2) {
        throw StateError('Import the second scorer log first.');
      }
      final rules = tournament.rulesFor(game);
      final maxSets = rules.maxSets;
      final effectiveTargets = setTargets ?? rules.setTargets;
      if (effectiveTargets.entries.any(
        (entry) => entry.key < 1 || entry.key > maxSets || entry.value < 1,
      )) {
        throw StateError(
          'Set targets must be positive and within the match format.',
        );
      }
      final effectiveRules = rules.copyWith(setTargets: effectiveTargets);
      if (setMappings.values.any(
        (mapping) => mapping.values.any((number) => number > maxSets),
      )) {
        throw StateError('A corrected set number exceeds the match format.');
      }
      const reconciliation = ReconciliationService();
      final result = reconciliation.compare(
        reconciliation.excludeRallies(
          reconciliation.remapSetNumbers(
            game.logs[0],
            setMappings[game.logs[0].id] ?? const {},
          ),
          (excludedRallyIds[game.logs[0].id] ?? const []).toSet(),
        ),
        reconciliation.excludeRallies(
          reconciliation.remapSetNumbers(
            game.logs[1],
            setMappings[game.logs[1].id] ?? const {},
          ),
          (excludedRallyIds[game.logs[1].id] ?? const []).toSet(),
        ),
      );
      final now = DateTime.now();
      final official = reconciliation.merge(
        result,
        preferImported: preferImported,
        officialLogId: _uuid.v4(),
        now: now,
        rallyOverrides: rallyOverrides,
      );
      if (setMappings.isNotEmpty || excludedRallyIds.isNotEmpty) {
        final setError = reconciliation.setSequenceError(official, maxSets);
        if (setError != null) throw StateError(setError);
      }
      if (excludedRallyIds.isNotEmpty) {
        final scoreError = const ScoringEngine().scoreProgressionReason(
          game,
          official,
        );
        if (scoreError != null) throw StateError(scoreError);
      }
      final excessReason = const ScoringEngine().excessRallyReason(
        official,
        effectiveRules,
      );
      if (excessReason != null) throw StateError(excessReason);
      final incompleteReason = const ScoringEngine().incompleteMatchReason(
        game,
        official,
        effectiveRules,
      );
      if (incompleteReason != null) {
        throw StateError(incompleteReason);
      }
      final revision = FinalizationRevision(
        id: _uuid.v4(),
        finalizedAt: now,
        reason: reason,
        officialLog: official,
        setMappings: setMappings,
        excludedRallyIds: excludedRallyIds,
        setTargets: effectiveTargets,
      );
      return game.copyWith(
        status: GameStatus.finalized,
        officialLog: official,
        rulesSnapshot: effectiveRules,
        revisions: [...game.revisions, revision],
      );
    });
  }

  Future<void> updateGameMatchFormat(
    String tournamentId,
    String gameId,
    int maxSets,
  ) async {
    if (maxSets != 1 && maxSets != 3 && maxSets != 5) {
      throw StateError(
        'Match format must be one set, best of three, or best of five.',
      );
    }
    await _updateGame(tournamentId, gameId, (tournament, game) {
      if (game.status == GameStatus.finalized) {
        throw StateError(
          'Reopen the finalized game before changing its format.',
        );
      }
      final rules = tournament.rulesFor(game);
      return game.copyWith(
        rulesSnapshot: rules.copyWith(
          maxSets: maxSets,
          setsToWin: (maxSets ~/ 2) + 1,
          setTargets: {
            for (final entry in rules.setTargets.entries)
              if (entry.key <= maxSets) entry.key: entry.value,
          },
        ),
      );
    });
  }

  Future<void> reopenGame(
    String tournamentId,
    String gameId,
    String reason,
  ) async {
    if (reason.trim().isEmpty) {
      throw StateError('A revision reason is required.');
    }
    await _updateGame(
      tournamentId,
      gameId,
      (tournament, game) => game.copyWith(
        status: GameStatus.awaitingReconciliation,
        clearOfficialLog: true,
      ),
    );
  }

  Future<void> deleteGame(String tournamentId, String gameId) async {
    await _updateTournament(tournamentId, (tournament) {
      if (!tournament.games.any((game) => game.id == gameId)) {
        throw StateError('Game not found.');
      }
      return tournament.copyWith(
        games: tournament.games.where((game) => game.id != gameId).toList(),
      );
    });
  }

  Future<void> deleteTournament(String tournamentId) async {
    if (!state.tournaments.any((item) => item.id == tournamentId)) {
      throw StateError('Tournament not found.');
    }
    await _commit(
      state.copyWith(
        tournaments: state.tournaments
            .where((item) => item.id != tournamentId)
            .toList(),
      ),
    );
  }

  Future<void> restoreBackup(AppData backup) => _commit(
    AppData(
      deviceId: state.deviceId,
      tournaments: backup.tournaments,
      importedPackageIds: backup.importedPackageIds,
      lastBackupAt: DateTime.now(),
    ),
  );

  Future<void> markBackedUp() =>
      _commit(state.copyWith(lastBackupAt: DateTime.now()));

  Future<void> _updateTournament(
    String tournamentId,
    Tournament Function(Tournament tournament) transform,
  ) async {
    final tournaments = [...state.tournaments];
    final index = tournaments.indexWhere((item) => item.id == tournamentId);
    if (index < 0) throw StateError('Tournament not found.');
    tournaments[index] = transform(tournaments[index]);
    await _commit(state.copyWith(tournaments: tournaments));
  }

  Future<void> _updateGame(
    String tournamentId,
    String gameId,
    Game Function(Tournament tournament, Game game) transform,
  ) => _updateTournament(tournamentId, (tournament) {
    final games = [...tournament.games];
    final index = games.indexWhere((item) => item.id == gameId);
    if (index < 0) throw StateError('Game not found.');
    games[index] = transform(tournament, games[index]);
    return tournament.copyWith(games: games);
  });
}
