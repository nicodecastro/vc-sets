import 'models.dart';

class RallyActionComposer {
  const RallyActionComposer();

  List<TeamAction> add(List<TeamAction> pending, TeamAction next) {
    if (next.grade != ActionGrade.attempt && pending.isNotEmpty) {
      final previous = pending.last;
      final gradesPreviousAttempt =
          previous.grade == ActionGrade.attempt &&
          previous.teamId == next.teamId &&
          previous.playerId == next.playerId &&
          previous.skill == next.skill;
      if (gradesPreviousAttempt) {
        return [
          ...pending.take(pending.length - 1),
          previous.copyWith(grade: next.grade),
        ];
      }
    }
    return [...pending, next];
  }
}

class MatchScore {
  const MatchScore({
    required this.setNumber,
    required this.homePoints,
    required this.awayPoints,
    required this.homeSets,
    required this.awaySets,
    required this.homeRotation,
    required this.awayRotation,
    required this.servingTeamId,
    required this.isComplete,
  });

  final int setNumber;
  final int homePoints;
  final int awayPoints;
  final int homeSets;
  final int awaySets;
  final int homeRotation;
  final int awayRotation;
  final String servingTeamId;
  final bool isComplete;
}

class ScoringEngine {
  const ScoringEngine();

  String? inferRallyWinner(
    Game game,
    String trackedTeamId,
    List<TeamAction> actions,
  ) {
    if (actions.isEmpty) return null;
    final last = actions.last;
    if (last.grade == ActionGrade.error) {
      return _otherTeam(game, trackedTeamId);
    }
    if (last.grade == ActionGrade.success &&
        (last.skill == Skill.serve ||
            last.skill == Skill.attack ||
            last.skill == Skill.block ||
            last.skill == Skill.opponentError)) {
      return trackedTeamId;
    }
    return null;
  }

  MatchScore score(Game game, ScorerLog log, MatchRules rules) {
    var homeSets = 0;
    var awaySets = 0;
    var setNumber = 1;
    var homePoints = 0;
    var awayPoints = 0;
    var homeRotation = 1;
    var awayRotation = 1;
    var serving = log.initialServingTeamId;

    for (final rally in log.rallies) {
      setNumber = rally.setNumber;
      homePoints = rally.homeScore;
      awayPoints = rally.awayScore;
      homeRotation = rally.homeRotation;
      awayRotation = rally.awayRotation;
      serving = rally.servingTeamId;
      if (isSetComplete(homePoints, awayPoints, setNumber, rules)) {
        if (homePoints > awayPoints) {
          homeSets++;
        } else {
          awaySets++;
        }
        if (homeSets < rules.setsToWin && awaySets < rules.setsToWin) {
          setNumber++;
          homePoints = 0;
          awayPoints = 0;
          homeRotation = 1;
          awayRotation = 1;
          serving = setNumber.isOdd
              ? log.initialServingTeamId
              : _otherTeam(game, log.initialServingTeamId);
        }
      }
    }

    return MatchScore(
      setNumber: setNumber,
      homePoints: homePoints,
      awayPoints: awayPoints,
      homeSets: homeSets,
      awaySets: awaySets,
      homeRotation: homeRotation,
      awayRotation: awayRotation,
      servingTeamId: serving,
      isComplete: homeSets >= rules.setsToWin || awaySets >= rules.setsToWin,
    );
  }

  bool isSetComplete(int home, int away, int setNumber, MatchRules rules) {
    final target = rules.maxSets > 1 && setNumber == rules.maxSets
        ? rules.decidingSetTarget
        : rules.regularSetTarget;
    return (home >= target || away >= target) &&
        (home - away).abs() >= rules.winBy;
  }

  String? incompleteMatchReason(Game game, ScorerLog log, MatchRules rules) {
    final current = score(game, log, rules);
    if (current.isComplete) return null;
    if (log.rallies.isEmpty) {
      return 'The reconciled log has no rallies. A team must win '
          '${rules.setsToWin} set(s) to complete this match.';
    }
    final target = rules.maxSets > 1 && current.setNumber == rules.maxSets
        ? rules.decidingSetTarget
        : rules.regularSetTarget;
    return 'The reconciled result is ${current.homeSets}-${current.awaySets} '
        'in sets, but ${rules.setsToWin} set win(s) are required. '
        'Set ${current.setNumber} is ${current.homePoints}-${current.awayPoints}; '
        'a team must reach $target with a ${rules.winBy}-point lead.';
  }

  Rally nextRally({
    required String id,
    required Game game,
    required ScorerLog log,
    required MatchRules rules,
    required String winnerTeamId,
    required DateTime recordedAt,
    List<TeamAction> actions = const [],
    String? overrideReason,
  }) {
    if (winnerTeamId != game.homeTeamId && winnerTeamId != game.awayTeamId) {
      throw ArgumentError.value(
        winnerTeamId,
        'winnerTeamId',
        'Not part of game',
      );
    }
    final current = score(game, log, rules);
    if (current.isComplete && overrideReason == null) {
      throw StateError('The match is already complete.');
    }
    var home = current.homePoints;
    var away = current.awayPoints;
    var homeRotation = current.homeRotation;
    var awayRotation = current.awayRotation;
    if (winnerTeamId == game.homeTeamId) {
      home++;
      if (current.servingTeamId != game.homeTeamId) {
        homeRotation = homeRotation % 6 + 1;
      }
    } else {
      away++;
      if (current.servingTeamId != game.awayTeamId) {
        awayRotation = awayRotation % 6 + 1;
      }
    }
    final setRallies = log.rallies.where(
      (rally) => rally.setNumber == current.setNumber,
    );
    return Rally(
      id: id,
      setNumber: current.setNumber,
      sequence: setRallies.length + 1,
      winnerTeamId: winnerTeamId,
      homeScore: home,
      awayScore: away,
      homeRotation: homeRotation,
      awayRotation: awayRotation,
      servingTeamId: winnerTeamId,
      recordedAt: recordedAt,
      actions: actions,
      overrideReason: overrideReason,
    );
  }

  List<String> validateStartingLineup(
    TournamentTeam team,
    List<String> playerIds,
  ) {
    final errors = <String>[];
    if (playerIds.length != 6) {
      errors.add('A starting lineup must contain six players.');
    }
    if (playerIds.toSet().length != playerIds.length) {
      errors.add('A player appears more than once.');
    }
    final rosterIds = team.players.map((player) => player.id).toSet();
    if (playerIds.any((id) => !rosterIds.contains(id))) {
      errors.add('The lineup contains a player outside the roster.');
    }
    if (playerIds
            .where((id) => team.players.firstWhere((p) => p.id == id).isLibero)
            .length >
        1) {
      errors.add('Only one libero can be in the tracked lineup.');
    }
    return errors;
  }

  String _otherTeam(Game game, String teamId) =>
      teamId == game.homeTeamId ? game.awayTeamId : game.homeTeamId;
}
