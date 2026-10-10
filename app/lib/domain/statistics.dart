import 'models.dart';
import 'scoring.dart';

class SkillSummary {
  const SkillSummary({
    required this.attempts,
    required this.successes,
    required this.errors,
    required this.positive,
  });

  final int attempts;
  final int successes;
  final int errors;
  final int positive;

  double get successRate => attempts == 0 ? 0 : successes / attempts;
}

class PlayerSummary {
  PlayerSummary(this.player, this.bySkill);
  final Player player;
  final Map<Skill, SkillSummary> bySkill;

  int get totalSuccesses =>
      bySkill.values.fold(0, (total, item) => total + item.successes);
}

const playerStatColumns = <String>[
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
];

class PlayerStatRow {
  const PlayerStatRow({
    required this.team,
    required this.player,
    required this.lastName,
    required this.counts,
    required this.gamesPlayed,
    required this.setsPlayed,
    required this.gamesWon,
  });

  final TournamentTeam team;
  final Player player;
  final String lastName;
  final Map<String, int> counts;
  final int gamesPlayed;
  final int setsPlayed;
  final int gamesWon;
}

class StandingRow {
  const StandingRow({
    required this.team,
    required this.played,
    required this.wins,
    required this.losses,
    required this.matchPoints,
    required this.setsWon,
    required this.setsLost,
    required this.pointsWon,
    required this.pointsLost,
  });

  final TournamentTeam team;
  final int played;
  final int wins;
  final int losses;
  final int matchPoints;
  final int setsWon;
  final int setsLost;
  final int pointsWon;
  final int pointsLost;

  double get setRatio =>
      setsLost == 0 ? setsWon.toDouble() : setsWon / setsLost;
  double get pointRatio =>
      pointsLost == 0 ? pointsWon.toDouble() : pointsWon / pointsLost;
}

class StatisticsService {
  const StatisticsService();

  List<PlayerStatRow> playerStatsSummary(Tournament tournament) {
    final finalizedGames = tournament.games
        .where(
          (game) =>
              game.status == GameStatus.finalized && game.officialLog != null,
        )
        .toList();
    final actions = finalizedGames
        .expand((game) => game.officialLog!.rallies)
        .expand((rally) => rally.actions)
        .toList();
    final rows = <PlayerStatRow>[];
    for (final team in tournament.teams) {
      final teamActions = actions
          .where((action) => action.teamId == team.id)
          .toList();
      final opponentErrors = teamActions
          .where((action) => action.skill == Skill.opponentError)
          .length;
      final teamFaults = teamActions
          .where((action) => action.skill == Skill.teamFault)
          .length;
      for (final player in team.players) {
        var gamesPlayed = 0;
        var setsPlayed = 0;
        var gamesWon = 0;
        for (final game in finalizedGames.where(
          (game) => game.homeTeamId == team.id || game.awayTeamId == team.id,
        )) {
          final log = game.officialLog!;
          final playedSets = <int>{
            for (final setNumber
                in log.rallies.map((rally) => rally.setNumber).toSet())
              if (_playedSet(log, team.id, player.id, setNumber)) setNumber,
          };
          if (playedSets.isEmpty) continue;
          gamesPlayed++;
          setsPlayed += playedSets.length;
          final result = _setResults(log, tournament.rulesFor(game));
          final teamWon = team.id == game.homeTeamId
              ? result.homeSets > result.awaySets
              : result.awaySets > result.homeSets;
          if (teamWon) gamesWon++;
        }
        final counts = <String, int>{
          for (final column in playerStatColumns) column: 0,
        };
        for (final action in teamActions.where(
          (action) => action.playerId == player.id,
        )) {
          final column = _playerStatColumn(action);
          if (column != null) counts[column] = counts[column]! + 1;
        }
        counts['OP+'] = opponentErrors;
        counts['T-'] = teamFaults;
        rows.add(
          PlayerStatRow(
            team: team,
            player: player,
            lastName: _lastName(player.name),
            counts: counts,
            gamesPlayed: gamesPlayed,
            setsPlayed: setsPlayed,
            gamesWon: gamesWon,
          ),
        );
      }
    }
    return rows;
  }

  List<PlayerSummary> playerSummaries(Tournament tournament) {
    final actions = tournament.games
        .where(
          (game) =>
              game.status == GameStatus.finalized && game.officialLog != null,
        )
        .expand((game) => game.officialLog!.rallies)
        .expand((rally) => rally.actions);
    final byPlayer = <String, List<TeamAction>>{};
    for (final action in actions) {
      if (action.playerId != null) {
        byPlayer.putIfAbsent(action.playerId!, () => []).add(action);
      }
    }
    final players = tournament.teams.expand((team) => team.players);
    return players
        .map((player) {
          final playerActions = byPlayer[player.id] ?? const <TeamAction>[];
          final skills = <Skill, SkillSummary>{};
          for (final skill in Skill.values.where(
            (item) =>
                item != Skill.timeout &&
                item != Skill.substitution &&
                item != Skill.opponentError &&
                item != Skill.teamFault,
          )) {
            final relevant = playerActions
                .where((action) => action.skill == skill)
                .toList();
            skills[skill] = SkillSummary(
              attempts: relevant.length,
              successes: relevant
                  .where((action) => action.grade == ActionGrade.success)
                  .length,
              errors: relevant
                  .where((action) => action.grade == ActionGrade.error)
                  .length,
              positive: relevant
                  .where((action) => action.grade == ActionGrade.positive)
                  .length,
            );
          }
          return PlayerSummary(player, skills);
        })
        .where(
          (summary) =>
              summary.bySkill.values.any((skill) => skill.attempts > 0),
        )
        .toList()
      ..sort((a, b) => b.totalSuccesses.compareTo(a.totalSuccesses));
  }

  List<StandingRow> standings(Tournament tournament, {int? poolNumber}) {
    final mutable = <String, _MutableStanding>{
      for (final team in tournament.teams)
        if (poolNumber == null || team.poolNumber == poolNumber)
          team.id: _MutableStanding(team),
    };
    for (final game in tournament.games.where(
      (game) =>
          game.stage == GameStage.pool &&
          (poolNumber == null ||
              game.poolNumber == poolNumber ||
              game.poolNumber == null &&
                  tournament.team(game.homeTeamId).poolNumber == poolNumber) &&
          game.status == GameStatus.finalized &&
          game.officialLog != null,
    )) {
      final home = mutable[game.homeTeamId];
      final away = mutable[game.awayTeamId];
      if (home == null || away == null) continue;
      final gameRules = tournament.rulesFor(game);
      final sets = _setResults(game.officialLog!, gameRules);
      home.played++;
      away.played++;
      home.setsWon += sets.homeSets;
      home.setsLost += sets.awaySets;
      away.setsWon += sets.awaySets;
      away.setsLost += sets.homeSets;
      for (final rally in game.officialLog!.rallies) {
        if (rally.winnerTeamId == game.homeTeamId) {
          home.pointsWon++;
          away.pointsLost++;
        } else {
          away.pointsWon++;
          home.pointsLost++;
        }
      }
      final homeWon = sets.homeSets > sets.awaySets;
      (homeWon ? home : away).wins++;
      (homeWon ? away : home).losses++;
      final deciding =
          gameRules.maxSets > 1 &&
          (sets.homeSets == gameRules.setsToWin &&
                  sets.awaySets == gameRules.setsToWin - 1 ||
              sets.awaySets == gameRules.setsToWin &&
                  sets.homeSets == gameRules.setsToWin - 1);
      final policy = gameRules.standings;
      if (deciding) {
        (homeWon ? home : away).matchPoints += policy.decidingWinPoints;
        (homeWon ? away : home).matchPoints += policy.decidingLossPoints;
      } else {
        (homeWon ? home : away).matchPoints += policy.clearWinPoints;
        (homeWon ? away : home).matchPoints += policy.clearLossPoints;
      }
    }
    final rows = mutable.values.map((item) => item.freeze()).toList();
    rows.sort((a, b) {
      for (final rule in tournament.effectivePoolRules.standings.tieBreakers) {
        final comparison = switch (rule) {
          'wins' => b.wins.compareTo(a.wins),
          'setRatio' => b.setRatio.compareTo(a.setRatio),
          'pointRatio' => b.pointRatio.compareTo(a.pointRatio),
          _ => b.matchPoints.compareTo(a.matchPoints),
        };
        if (comparison != 0) return comparison;
      }
      return a.team.name.compareTo(b.team.name);
    });
    return rows;
  }

  ({int homeSets, int awaySets}) _setResults(ScorerLog log, MatchRules rules) {
    var homeSets = 0;
    var awaySets = 0;
    for (final set in <int>{...log.rallies.map((rally) => rally.setNumber)}) {
      final last = log.rallies.where((rally) => rally.setNumber == set).last;
      if (const ScoringEngine().isSetComplete(
        last.homeScore,
        last.awayScore,
        set,
        rules,
      )) {
        last.homeScore > last.awayScore ? homeSets++ : awaySets++;
      }
    }
    return (homeSets: homeSets, awaySets: awaySets);
  }

  bool _playedSet(
    ScorerLog log,
    String teamId,
    String playerId,
    int setNumber,
  ) {
    if (log.lineupFor(teamId, setNumber)?.playerIds.contains(playerId) ??
        false) {
      return true;
    }
    if (log.substitutions.any(
      (item) =>
          item.teamId == teamId &&
          item.setNumber == setNumber &&
          (item.playerInId == playerId || item.playerOutId == playerId),
    )) {
      return true;
    }
    return log.rallies
        .where((rally) => rally.setNumber == setNumber)
        .expand((rally) => rally.actions)
        .any(
          (action) => action.teamId == teamId && action.playerId == playerId,
        );
  }

  String? _playerStatColumn(TeamAction action) {
    final code = switch (action.skill) {
      Skill.set => 'S',
      Skill.serve => 'V',
      Skill.dig => 'D',
      Skill.reception => 'R',
      Skill.attack => 'A',
      Skill.block => 'B',
      _ => null,
    };
    if (code == null) return null;
    final suffix = switch (action.grade) {
      ActionGrade.success || ActionGrade.positive => '+',
      ActionGrade.error => '-',
      ActionGrade.attempt || ActionGrade.neutral => '',
    };
    return '$code$suffix';
  }

  String _lastName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.last;
  }
}

class _MutableStanding {
  _MutableStanding(this.team);
  final TournamentTeam team;
  int played = 0;
  int wins = 0;
  int losses = 0;
  int matchPoints = 0;
  int setsWon = 0;
  int setsLost = 0;
  int pointsWon = 0;
  int pointsLost = 0;

  StandingRow freeze() => StandingRow(
    team: team,
    played: played,
    wins: wins,
    losses: losses,
    matchPoints: matchPoints,
    setsWon: setsWon,
    setsLost: setsLost,
    pointsWon: pointsWon,
    pointsLost: pointsLost,
  );
}
