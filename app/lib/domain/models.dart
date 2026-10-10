import 'dart:convert';

enum TournamentStatus { draft, active, completed }

enum GameStatus { scheduled, inProgress, awaitingReconciliation, finalized }

enum GameStage { pool, bracket }

enum TournamentFormat { roundRobin, poolsThenKnockout, knockoutOnly }

enum BracketGameType { standard, finalMatch, thirdPlace }

enum SubstitutionKind { regular, liberoReplacement }

enum PlayerPosition { S, OH, OPP, MB, L, DS, U }

enum Skill {
  serve,
  reception,
  set,
  attack,
  block,
  dig,
  error,
  substitution,
  timeout,
  opponentError,
  teamFault,
}

enum ActionGrade { success, positive, neutral, error, attempt }

T enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  return values.where((item) => item.name == value).firstOrNull ?? fallback;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class Player {
  const Player({
    required this.id,
    required this.number,
    required this.name,
    required this.position,
    this.isCaptain = false,
  });

  final String id;
  final int number;
  final String name;
  final PlayerPosition position;
  final bool isCaptain;

  bool get isLibero => position == PlayerPosition.L;

  Map<String, Object?> toJson() => {
    'id': id,
    'number': number,
    'name': name,
    'position': position.name,
    'isCaptain': isCaptain,
  };

  factory Player.fromJson(Map<String, Object?> json) => Player(
    id: json['id']! as String,
    number: (json['number'] as num).toInt(),
    name: json['name']! as String,
    position: enumByName(
      PlayerPosition.values,
      json['position'] == 'UT' ? 'U' : json['position'],
      PlayerPosition.U,
    ),
    isCaptain: json['isCaptain'] as bool? ?? false,
  );
}

class TournamentTeam {
  const TournamentTeam({
    required this.id,
    required this.name,
    required this.shortCode,
    required this.colorValue,
    this.poolNumber = 1,
    this.players = const [],
  });

  final String id;
  final String name;
  final String shortCode;
  final int colorValue;
  final int poolNumber;
  final List<Player> players;

  TournamentTeam copyWith({int? poolNumber, List<Player>? players}) =>
      TournamentTeam(
        id: id,
        name: name,
        shortCode: shortCode,
        colorValue: colorValue,
        poolNumber: poolNumber ?? this.poolNumber,
        players: players ?? this.players,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'shortCode': shortCode,
    'colorValue': colorValue,
    'poolNumber': poolNumber,
    'players': players.map((player) => player.toJson()).toList(),
  };

  factory TournamentTeam.fromJson(Map<String, Object?> json) => TournamentTeam(
    id: json['id']! as String,
    name: json['name']! as String,
    shortCode: json['shortCode']! as String,
    colorValue: (json['colorValue'] as num).toInt(),
    poolNumber: (json['poolNumber'] as num?)?.toInt() ?? 1,
    players: (json['players'] as List<Object?>? ?? const [])
        .map((item) => Player.fromJson((item as Map).cast<String, Object?>()))
        .toList(),
  );
}

class StandingsPolicy {
  const StandingsPolicy({
    this.clearWinPoints = 3,
    this.decidingWinPoints = 2,
    this.decidingLossPoints = 1,
    this.clearLossPoints = 0,
    this.tieBreakers = const [
      'matchPoints',
      'wins',
      'setRatio',
      'pointRatio',
      'headToHead',
    ],
  });

  final int clearWinPoints;
  final int decidingWinPoints;
  final int decidingLossPoints;
  final int clearLossPoints;
  final List<String> tieBreakers;

  Map<String, Object?> toJson() => {
    'clearWinPoints': clearWinPoints,
    'decidingWinPoints': decidingWinPoints,
    'decidingLossPoints': decidingLossPoints,
    'clearLossPoints': clearLossPoints,
    'tieBreakers': tieBreakers,
  };

  factory StandingsPolicy.fromJson(Map<String, Object?> json) =>
      StandingsPolicy(
        clearWinPoints: (json['clearWinPoints'] as num?)?.toInt() ?? 3,
        decidingWinPoints: (json['decidingWinPoints'] as num?)?.toInt() ?? 2,
        decidingLossPoints: (json['decidingLossPoints'] as num?)?.toInt() ?? 1,
        clearLossPoints: (json['clearLossPoints'] as num?)?.toInt() ?? 0,
        tieBreakers: (json['tieBreakers'] as List<Object?>? ?? const [])
            .cast<String>(),
      );
}

class MatchRules {
  const MatchRules({
    this.setsToWin = 3,
    this.regularSetTarget = 25,
    this.decidingSetTarget = 15,
    this.winBy = 2,
    this.maxSets = 5,
    this.standings = const StandingsPolicy(),
  });

  final int setsToWin;
  final int regularSetTarget;
  final int decidingSetTarget;
  final int winBy;
  final int maxSets;
  final StandingsPolicy standings;

  MatchRules copyWith({
    int? setsToWin,
    int? regularSetTarget,
    int? decidingSetTarget,
    int? winBy,
    int? maxSets,
    StandingsPolicy? standings,
  }) => MatchRules(
    setsToWin: setsToWin ?? this.setsToWin,
    regularSetTarget: regularSetTarget ?? this.regularSetTarget,
    decidingSetTarget: decidingSetTarget ?? this.decidingSetTarget,
    winBy: winBy ?? this.winBy,
    maxSets: maxSets ?? this.maxSets,
    standings: standings ?? this.standings,
  );

  Map<String, Object?> toJson() => {
    'setsToWin': setsToWin,
    'regularSetTarget': regularSetTarget,
    'decidingSetTarget': decidingSetTarget,
    'winBy': winBy,
    'maxSets': maxSets,
    'standings': standings.toJson(),
  };

  factory MatchRules.fromJson(Map<String, Object?> json) => MatchRules(
    setsToWin: (json['setsToWin'] as num?)?.toInt() ?? 3,
    regularSetTarget: (json['regularSetTarget'] as num?)?.toInt() ?? 25,
    decidingSetTarget: (json['decidingSetTarget'] as num?)?.toInt() ?? 15,
    winBy: (json['winBy'] as num?)?.toInt() ?? 2,
    maxSets: (json['maxSets'] as num?)?.toInt() ?? 5,
    standings: StandingsPolicy.fromJson(
      ((json['standings'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
  );
}

class TeamAction {
  const TeamAction({
    required this.id,
    required this.teamId,
    required this.skill,
    required this.grade,
    required this.recordedAt,
    this.playerId,
    this.note,
    this.metadata = const {},
  });

  final String id;
  final String teamId;
  final String? playerId;
  final Skill skill;
  final ActionGrade grade;
  final DateTime recordedAt;
  final String? note;
  final Map<String, Object?> metadata;

  TeamAction copyWith({ActionGrade? grade}) => TeamAction(
    id: id,
    teamId: teamId,
    playerId: playerId,
    skill: skill,
    grade: grade ?? this.grade,
    recordedAt: recordedAt,
    note: note,
    metadata: metadata,
  );

  String notation(TournamentTeam team) {
    if (skill == Skill.opponentError) return 'OP+';
    if (skill == Skill.teamFault) return 'T-';
    final code = switch (skill) {
      Skill.serve => 'V',
      Skill.attack => 'A',
      Skill.block => 'B',
      Skill.set => 'S',
      Skill.reception => 'R',
      Skill.dig => 'D',
      Skill.error => 'E',
      Skill.substitution => 'SUB',
      Skill.timeout => 'TO',
      Skill.opponentError => 'OP',
      Skill.teamFault => 'T',
    };
    final player = playerId == null
        ? null
        : team.players.where((item) => item.id == playerId).firstOrNull;
    final number = player == null ? '' : '${player.number}';
    final suffix = switch (grade) {
      ActionGrade.success || ActionGrade.positive => '+',
      ActionGrade.error => '-',
      ActionGrade.neutral || ActionGrade.attempt => '',
    };
    return '$code$number$suffix';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'teamId': teamId,
    'playerId': playerId,
    'skill': skill.name,
    'grade': grade.name,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'note': note,
    'metadata': metadata,
  };

  factory TeamAction.fromJson(Map<String, Object?> json) => TeamAction(
    id: json['id']! as String,
    teamId: json['teamId']! as String,
    playerId: json['playerId'] as String?,
    skill: enumByName(Skill.values, json['skill'], Skill.error),
    grade: enumByName(ActionGrade.values, json['grade'], ActionGrade.neutral),
    recordedAt: DateTime.parse(json['recordedAt']! as String),
    note: json['note'] as String?,
    metadata: ((json['metadata'] as Map?) ?? const {}).cast<String, Object?>(),
  );
}

class Rally {
  const Rally({
    required this.id,
    required this.setNumber,
    required this.sequence,
    required this.winnerTeamId,
    required this.homeScore,
    required this.awayScore,
    required this.homeRotation,
    required this.awayRotation,
    required this.servingTeamId,
    required this.recordedAt,
    this.actions = const [],
    this.overrideReason,
    this.correctionOf,
  });

  final String id;
  final int setNumber;
  final int sequence;
  final String winnerTeamId;
  final int homeScore;
  final int awayScore;
  final int homeRotation;
  final int awayRotation;
  final String servingTeamId;
  final DateTime recordedAt;
  final List<TeamAction> actions;
  final String? overrideReason;
  final String? correctionOf;

  String get alignmentKey => '$setNumber:$sequence';

  Map<String, Object?> toJson() => {
    'id': id,
    'setNumber': setNumber,
    'sequence': sequence,
    'winnerTeamId': winnerTeamId,
    'homeScore': homeScore,
    'awayScore': awayScore,
    'homeRotation': homeRotation,
    'awayRotation': awayRotation,
    'servingTeamId': servingTeamId,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'actions': actions.map((action) => action.toJson()).toList(),
    'overrideReason': overrideReason,
    'correctionOf': correctionOf,
  };

  factory Rally.fromJson(Map<String, Object?> json) => Rally(
    id: json['id']! as String,
    setNumber: (json['setNumber'] as num).toInt(),
    sequence: (json['sequence'] as num).toInt(),
    winnerTeamId: json['winnerTeamId']! as String,
    homeScore: (json['homeScore'] as num).toInt(),
    awayScore: (json['awayScore'] as num).toInt(),
    homeRotation: (json['homeRotation'] as num?)?.toInt() ?? 1,
    awayRotation: (json['awayRotation'] as num?)?.toInt() ?? 1,
    servingTeamId: json['servingTeamId']! as String,
    recordedAt: DateTime.parse(json['recordedAt']! as String),
    actions: (json['actions'] as List<Object?>? ?? const [])
        .map(
          (item) => TeamAction.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
    overrideReason: json['overrideReason'] as String?,
    correctionOf: json['correctionOf'] as String?,
  );
}

class Correction {
  const Correction({
    required this.id,
    required this.rallyId,
    required this.reason,
    required this.correctedAt,
    required this.kind,
  });

  final String id;
  final String rallyId;
  final String reason;
  final DateTime correctedAt;
  final String kind;

  Map<String, Object?> toJson() => {
    'id': id,
    'rallyId': rallyId,
    'reason': reason,
    'correctedAt': correctedAt.toUtc().toIso8601String(),
    'kind': kind,
  };

  factory Correction.fromJson(Map<String, Object?> json) => Correction(
    id: json['id']! as String,
    rallyId: json['rallyId']! as String,
    reason: json['reason']! as String,
    correctedAt: DateTime.parse(json['correctedAt']! as String),
    kind: json['kind']! as String,
  );
}

class LineupSnapshot {
  const LineupSnapshot({
    required this.teamId,
    required this.playerIds,
    this.setNumber = 1,
    this.rotation = 1,
    this.recordedAt,
  });

  final String teamId;
  final List<String> playerIds;
  final int setNumber;
  final int rotation;
  final DateTime? recordedAt;

  Map<String, Object?> toJson() => {
    'teamId': teamId,
    'playerIds': playerIds,
    'setNumber': setNumber,
    'rotation': rotation,
    'recordedAt': recordedAt?.toUtc().toIso8601String(),
  };

  factory LineupSnapshot.fromJson(Map<String, Object?> json) => LineupSnapshot(
    teamId: json['teamId']! as String,
    playerIds: (json['playerIds'] as List<Object?>).cast<String>(),
    setNumber: (json['setNumber'] as num?)?.toInt() ?? 1,
    rotation: (json['rotation'] as num?)?.toInt() ?? 1,
    recordedAt: json['recordedAt'] == null
        ? null
        : DateTime.parse(json['recordedAt']! as String),
  );
}

class Substitution {
  const Substitution({
    required this.id,
    required this.teamId,
    required this.setNumber,
    required this.playerOutId,
    required this.playerInId,
    required this.homeScore,
    required this.awayScore,
    required this.recordedAt,
    this.kind = SubstitutionKind.regular,
  });

  final String id;
  final String teamId;
  final int setNumber;
  final String playerOutId;
  final String playerInId;
  final int homeScore;
  final int awayScore;
  final DateTime recordedAt;
  final SubstitutionKind kind;

  bool get isLiberoReplacement => kind == SubstitutionKind.liberoReplacement;

  Map<String, Object?> toJson() => {
    'id': id,
    'teamId': teamId,
    'setNumber': setNumber,
    'playerOutId': playerOutId,
    'playerInId': playerInId,
    'homeScore': homeScore,
    'awayScore': awayScore,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'kind': kind.name,
  };

  factory Substitution.fromJson(Map<String, Object?> json) => Substitution(
    id: json['id']! as String,
    teamId: json['teamId']! as String,
    setNumber: (json['setNumber'] as num).toInt(),
    playerOutId: json['playerOutId']! as String,
    playerInId: json['playerInId']! as String,
    homeScore: (json['homeScore'] as num?)?.toInt() ?? 0,
    awayScore: (json['awayScore'] as num?)?.toInt() ?? 0,
    recordedAt: DateTime.parse(json['recordedAt']! as String),
    kind: enumByName(
      SubstitutionKind.values,
      json['kind'],
      SubstitutionKind.regular,
    ),
  );
}

class TeamTimeout {
  const TeamTimeout({
    required this.id,
    required this.teamId,
    required this.setNumber,
    required this.homeScore,
    required this.awayScore,
    required this.recordedAt,
  });

  final String id;
  final String teamId;
  final int setNumber;
  final int homeScore;
  final int awayScore;
  final DateTime recordedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'teamId': teamId,
    'setNumber': setNumber,
    'homeScore': homeScore,
    'awayScore': awayScore,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };

  factory TeamTimeout.fromJson(Map<String, Object?> json) => TeamTimeout(
    id: json['id']! as String,
    teamId: json['teamId']! as String,
    setNumber: (json['setNumber'] as num).toInt(),
    homeScore: (json['homeScore'] as num?)?.toInt() ?? 0,
    awayScore: (json['awayScore'] as num?)?.toInt() ?? 0,
    recordedAt: DateTime.parse(json['recordedAt']! as String),
  );
}

class ScorerLog {
  const ScorerLog({
    required this.id,
    required this.gameId,
    required this.assignedTeamId,
    required this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    required this.initialServingTeamId,
    this.lineups = const [],
    this.substitutions = const [],
    this.timeouts = const [],
    this.rallies = const [],
    this.corrections = const [],
  });

  final String id;
  final String gameId;
  final String assignedTeamId;
  final String deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String initialServingTeamId;
  final List<LineupSnapshot> lineups;
  final List<Substitution> substitutions;
  final List<TeamTimeout> timeouts;
  final List<Rally> rallies;
  final List<Correction> corrections;

  ScorerLog copyWith({
    DateTime? updatedAt,
    List<Rally>? rallies,
    List<Correction>? corrections,
    List<LineupSnapshot>? lineups,
    List<Substitution>? substitutions,
    List<TeamTimeout>? timeouts,
  }) => ScorerLog(
    id: id,
    gameId: gameId,
    assignedTeamId: assignedTeamId,
    deviceId: deviceId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    initialServingTeamId: initialServingTeamId,
    lineups: lineups ?? this.lineups,
    substitutions: substitutions ?? this.substitutions,
    timeouts: timeouts ?? this.timeouts,
    rallies: rallies ?? this.rallies,
    corrections: corrections ?? this.corrections,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'gameId': gameId,
    'assignedTeamId': assignedTeamId,
    'deviceId': deviceId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'initialServingTeamId': initialServingTeamId,
    'lineups': lineups.map((lineup) => lineup.toJson()).toList(),
    'substitutions': substitutions.map((item) => item.toJson()).toList(),
    'timeouts': timeouts.map((item) => item.toJson()).toList(),
    'rallies': rallies.map((rally) => rally.toJson()).toList(),
    'corrections': corrections.map((item) => item.toJson()).toList(),
  };

  factory ScorerLog.fromJson(Map<String, Object?> json) => ScorerLog(
    id: json['id']! as String,
    gameId: json['gameId']! as String,
    assignedTeamId: json['assignedTeamId']! as String,
    deviceId: json['deviceId']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    initialServingTeamId: json['initialServingTeamId']! as String,
    lineups: (json['lineups'] as List<Object?>? ?? const [])
        .map(
          (item) =>
              LineupSnapshot.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
    substitutions: (json['substitutions'] as List<Object?>? ?? const [])
        .map(
          (item) =>
              Substitution.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
    timeouts: (json['timeouts'] as List<Object?>? ?? const [])
        .map(
          (item) => TeamTimeout.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
    rallies: (json['rallies'] as List<Object?>? ?? const [])
        .map((item) => Rally.fromJson((item as Map).cast<String, Object?>()))
        .toList(),
    corrections: (json['corrections'] as List<Object?>? ?? const [])
        .map(
          (item) => Correction.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
  );

  LineupSnapshot? lineupFor(String teamId, int setNumber) {
    final candidates = lineups
        .where(
          (lineup) => lineup.teamId == teamId && lineup.setNumber <= setNumber,
        )
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final setComparison = a.setNumber.compareTo(b.setNumber);
      if (setComparison != 0) return setComparison;
      final aTime = a.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });
    return candidates.last;
  }

  List<String> serviceOrderFor(String teamId, int setNumber) {
    final lineup = lineupFor(teamId, setNumber);
    if (lineup == null) return const [];
    final players = [...lineup.playerIds];
    for (final substitution in substitutions.where(
      (item) => item.teamId == teamId && item.setNumber == setNumber,
    )) {
      final index = players.indexOf(substitution.playerOutId);
      if (index >= 0) players[index] = substitution.playerInId;
    }
    return players;
  }

  List<String> courtOrderFor(String teamId, int setNumber, int rotation) {
    final serviceOrder = serviceOrderFor(teamId, setNumber);
    if (serviceOrder.length != 6) return serviceOrder;
    return [
      for (var position = 1; position <= 6; position++)
        serviceOrder[(position + rotation - 2) % 6],
    ];
  }
}

class FinalizationRevision {
  const FinalizationRevision({
    required this.id,
    required this.finalizedAt,
    required this.reason,
    required this.officialLog,
  });

  final String id;
  final DateTime finalizedAt;
  final String reason;
  final ScorerLog officialLog;

  Map<String, Object?> toJson() => {
    'id': id,
    'finalizedAt': finalizedAt.toUtc().toIso8601String(),
    'reason': reason,
    'officialLog': officialLog.toJson(),
  };

  factory FinalizationRevision.fromJson(Map<String, Object?> json) =>
      FinalizationRevision(
        id: json['id']! as String,
        finalizedAt: DateTime.parse(json['finalizedAt']! as String),
        reason: json['reason']! as String,
        officialLog: ScorerLog.fromJson(
          (json['officialLog']! as Map).cast<String, Object?>(),
        ),
      );
}

class Game {
  const Game({
    required this.id,
    required this.tournamentId,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.scheduledAt,
    required this.venue,
    this.stage = GameStage.pool,
    this.poolNumber,
    this.bracketRound,
    this.bracketOrder,
    this.bracketType = BracketGameType.standard,
    this.rulesSnapshot,
    this.status = GameStatus.scheduled,
    this.logs = const [],
    this.officialLog,
    this.revisions = const [],
  });

  final String id;
  final String tournamentId;
  final String homeTeamId;
  final String awayTeamId;
  final DateTime scheduledAt;
  final String venue;
  final GameStage stage;
  final int? poolNumber;
  final int? bracketRound;
  final int? bracketOrder;
  final BracketGameType bracketType;
  final MatchRules? rulesSnapshot;
  final GameStatus status;
  final List<ScorerLog> logs;
  final ScorerLog? officialLog;
  final List<FinalizationRevision> revisions;

  Game copyWith({
    GameStatus? status,
    List<ScorerLog>? logs,
    ScorerLog? officialLog,
    bool clearOfficialLog = false,
    List<FinalizationRevision>? revisions,
  }) => Game(
    id: id,
    tournamentId: tournamentId,
    homeTeamId: homeTeamId,
    awayTeamId: awayTeamId,
    scheduledAt: scheduledAt,
    venue: venue,
    stage: stage,
    poolNumber: poolNumber,
    bracketRound: bracketRound,
    bracketOrder: bracketOrder,
    bracketType: bracketType,
    rulesSnapshot: rulesSnapshot,
    status: status ?? this.status,
    logs: logs ?? this.logs,
    officialLog: clearOfficialLog ? null : (officialLog ?? this.officialLog),
    revisions: revisions ?? this.revisions,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'tournamentId': tournamentId,
    'homeTeamId': homeTeamId,
    'awayTeamId': awayTeamId,
    'scheduledAt': scheduledAt.toUtc().toIso8601String(),
    'venue': venue,
    'stage': stage.name,
    'poolNumber': poolNumber,
    'bracketRound': bracketRound,
    'bracketOrder': bracketOrder,
    'bracketType': bracketType.name,
    'rulesSnapshot': rulesSnapshot?.toJson(),
    'status': status.name,
    'logs': logs.map((log) => log.toJson()).toList(),
    'officialLog': officialLog?.toJson(),
    'revisions': revisions.map((revision) => revision.toJson()).toList(),
  };

  factory Game.fromJson(Map<String, Object?> json) => Game(
    id: json['id']! as String,
    tournamentId: json['tournamentId']! as String,
    homeTeamId: json['homeTeamId']! as String,
    awayTeamId: json['awayTeamId']! as String,
    scheduledAt: DateTime.parse(json['scheduledAt']! as String),
    venue: json['venue'] as String? ?? '',
    stage: enumByName(GameStage.values, json['stage'], GameStage.pool),
    poolNumber: (json['poolNumber'] as num?)?.toInt(),
    bracketRound: (json['bracketRound'] as num?)?.toInt(),
    bracketOrder: (json['bracketOrder'] as num?)?.toInt(),
    bracketType: enumByName(
      BracketGameType.values,
      json['bracketType'],
      BracketGameType.standard,
    ),
    rulesSnapshot: json['rulesSnapshot'] == null
        ? null
        : MatchRules.fromJson(
            (json['rulesSnapshot']! as Map).cast<String, Object?>(),
          ),
    status: enumByName(GameStatus.values, json['status'], GameStatus.scheduled),
    logs: (json['logs'] as List<Object?>? ?? const [])
        .map(
          (item) => ScorerLog.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
    officialLog: json['officialLog'] == null
        ? null
        : ScorerLog.fromJson(
            (json['officialLog']! as Map).cast<String, Object?>(),
          ),
    revisions: (json['revisions'] as List<Object?>? ?? const [])
        .map(
          (item) => FinalizationRevision.fromJson(
            (item as Map).cast<String, Object?>(),
          ),
        )
        .toList(),
  );
}

class Tournament {
  const Tournament({
    required this.id,
    required this.name,
    required this.venue,
    required this.startsOn,
    required this.endsOn,
    required this.createdAt,
    this.status = TournamentStatus.draft,
    this.rules = const MatchRules(),
    TournamentFormat? format,
    int? knockoutSize,
    bool? bracketEnabled,
    int? bracketSize,
    this.poolCount = 1,
    this.qualifiersPerPool = 2,
    this.thirdPlaceEnabled = false,
    this.poolRules,
    this.semifinalRules,
    this.finalRules,
    this.thirdPlaceRules,
    this.teams = const [],
    this.games = const [],
  }) : format =
           format ??
           ((bracketEnabled ?? false)
               ? TournamentFormat.poolsThenKnockout
               : TournamentFormat.roundRobin),
       knockoutSize = knockoutSize ?? bracketSize ?? 2;

  final String id;
  final String name;
  final String venue;
  final DateTime startsOn;
  final DateTime endsOn;
  final DateTime createdAt;
  final TournamentStatus status;
  final MatchRules rules;
  final TournamentFormat format;
  final int poolCount;
  final int qualifiersPerPool;
  final int knockoutSize;
  final bool thirdPlaceEnabled;
  final MatchRules? poolRules;
  final MatchRules? semifinalRules;
  final MatchRules? finalRules;
  final MatchRules? thirdPlaceRules;
  final List<TournamentTeam> teams;
  final List<Game> games;

  bool get bracketEnabled => format != TournamentFormat.roundRobin;
  int get bracketSize => format == TournamentFormat.poolsThenKnockout
      ? poolCount * qualifiersPerPool
      : knockoutSize;

  MatchRules get effectivePoolRules => poolRules ?? rules;
  MatchRules get effectiveSemifinalRules => semifinalRules ?? rules;
  MatchRules get effectiveFinalRules => finalRules ?? rules;
  MatchRules get effectiveThirdPlaceRules => thirdPlaceRules ?? rules;

  MatchRules rulesFor(Game game) {
    if (game.rulesSnapshot != null) return game.rulesSnapshot!;
    if (game.stage == GameStage.pool) return effectivePoolRules;
    return switch (game.bracketType) {
      BracketGameType.finalMatch => effectiveFinalRules,
      BracketGameType.thirdPlace => effectiveThirdPlaceRules,
      BracketGameType.standard => effectiveSemifinalRules,
    };
  }

  Tournament copyWith({
    String? name,
    String? venue,
    DateTime? startsOn,
    DateTime? endsOn,
    TournamentStatus? status,
    MatchRules? rules,
    TournamentFormat? format,
    int? poolCount,
    int? qualifiersPerPool,
    int? knockoutSize,
    bool? thirdPlaceEnabled,
    MatchRules? poolRules,
    MatchRules? semifinalRules,
    MatchRules? finalRules,
    MatchRules? thirdPlaceRules,
    bool? bracketEnabled,
    int? bracketSize,
    List<TournamentTeam>? teams,
    List<Game>? games,
  }) => Tournament(
    id: id,
    name: name ?? this.name,
    venue: venue ?? this.venue,
    startsOn: startsOn ?? this.startsOn,
    endsOn: endsOn ?? this.endsOn,
    createdAt: createdAt,
    status: status ?? this.status,
    rules: rules ?? this.rules,
    format:
        format ??
        (bracketEnabled == null
            ? this.format
            : (bracketEnabled
                  ? TournamentFormat.poolsThenKnockout
                  : TournamentFormat.roundRobin)),
    poolCount: poolCount ?? this.poolCount,
    qualifiersPerPool: qualifiersPerPool ?? this.qualifiersPerPool,
    knockoutSize: knockoutSize ?? bracketSize ?? this.knockoutSize,
    thirdPlaceEnabled: thirdPlaceEnabled ?? this.thirdPlaceEnabled,
    poolRules: poolRules ?? this.poolRules,
    semifinalRules: semifinalRules ?? this.semifinalRules,
    finalRules: finalRules ?? this.finalRules,
    thirdPlaceRules: thirdPlaceRules ?? this.thirdPlaceRules,
    teams: teams ?? this.teams,
    games: games ?? this.games,
  );

  TournamentTeam team(String teamId) =>
      teams.firstWhere((team) => team.id == teamId);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'venue': venue,
    'startsOn': startsOn.toUtc().toIso8601String(),
    'endsOn': endsOn.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'rules': rules.toJson(),
    'format': format.name,
    'poolCount': poolCount,
    'qualifiersPerPool': qualifiersPerPool,
    'knockoutSize': knockoutSize,
    'thirdPlaceEnabled': thirdPlaceEnabled,
    'poolRules': poolRules?.toJson(),
    'semifinalRules': semifinalRules?.toJson(),
    'finalRules': finalRules?.toJson(),
    'thirdPlaceRules': thirdPlaceRules?.toJson(),
    'bracketEnabled': bracketEnabled,
    'bracketSize': bracketSize,
    'teams': teams.map((team) => team.toJson()).toList(),
    'games': games.map((game) => game.toJson()).toList(),
  };

  factory Tournament.fromJson(Map<String, Object?> json) => Tournament(
    id: json['id']! as String,
    name: json['name']! as String,
    venue: json['venue'] as String? ?? '',
    startsOn: DateTime.parse(json['startsOn']! as String),
    endsOn: DateTime.parse(json['endsOn']! as String),
    createdAt: DateTime.parse(json['createdAt']! as String),
    status: enumByName(
      TournamentStatus.values,
      json['status'],
      TournamentStatus.draft,
    ),
    rules: MatchRules.fromJson(
      ((json['rules'] as Map?) ?? const {}).cast<String, Object?>(),
    ),
    format: json['format'] == null
        ? null
        : enumByName(
            TournamentFormat.values,
            json['format'],
            TournamentFormat.roundRobin,
          ),
    poolCount: (json['poolCount'] as num?)?.toInt() ?? 1,
    qualifiersPerPool:
        (json['qualifiersPerPool'] as num?)?.toInt() ??
        (json['format'] == null && (json['bracketEnabled'] as bool? ?? false)
            ? (json['bracketSize'] as num?)?.toInt() ?? 2
            : 2),
    knockoutSize: (json['knockoutSize'] as num?)?.toInt(),
    thirdPlaceEnabled: json['thirdPlaceEnabled'] as bool? ?? false,
    poolRules: json['poolRules'] == null
        ? null
        : MatchRules.fromJson(
            (json['poolRules']! as Map).cast<String, Object?>(),
          ),
    semifinalRules: json['semifinalRules'] == null
        ? null
        : MatchRules.fromJson(
            (json['semifinalRules']! as Map).cast<String, Object?>(),
          ),
    finalRules: json['finalRules'] == null
        ? null
        : MatchRules.fromJson(
            (json['finalRules']! as Map).cast<String, Object?>(),
          ),
    thirdPlaceRules: json['thirdPlaceRules'] == null
        ? null
        : MatchRules.fromJson(
            (json['thirdPlaceRules']! as Map).cast<String, Object?>(),
          ),
    bracketEnabled: json['bracketEnabled'] as bool? ?? false,
    bracketSize: (json['bracketSize'] as num?)?.toInt() ?? 2,
    teams: (json['teams'] as List<Object?>? ?? const [])
        .map(
          (item) =>
              TournamentTeam.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
    games: (json['games'] as List<Object?>? ?? const [])
        .map((item) => Game.fromJson((item as Map).cast<String, Object?>()))
        .toList(),
  );
}

class AppData {
  const AppData({
    required this.deviceId,
    this.tournaments = const [],
    this.importedPackageIds = const [],
    this.lastBackupAt,
  });

  final String deviceId;
  final List<Tournament> tournaments;
  final List<String> importedPackageIds;
  final DateTime? lastBackupAt;

  AppData copyWith({
    List<Tournament>? tournaments,
    List<String>? importedPackageIds,
    DateTime? lastBackupAt,
  }) => AppData(
    deviceId: deviceId,
    tournaments: tournaments ?? this.tournaments,
    importedPackageIds: importedPackageIds ?? this.importedPackageIds,
    lastBackupAt: lastBackupAt ?? this.lastBackupAt,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': 5,
    'deviceId': deviceId,
    'tournaments': tournaments.map((item) => item.toJson()).toList(),
    'importedPackageIds': importedPackageIds,
    'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  factory AppData.decode(String source) =>
      AppData.fromJson((jsonDecode(source) as Map).cast<String, Object?>());

  factory AppData.fromJson(Map<String, Object?> json) => AppData(
    deviceId: json['deviceId']! as String,
    tournaments: (json['tournaments'] as List<Object?>? ?? const [])
        .map(
          (item) => Tournament.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(),
    importedPackageIds:
        (json['importedPackageIds'] as List<Object?>? ?? const [])
            .cast<String>(),
    lastBackupAt: json['lastBackupAt'] == null
        ? null
        : DateTime.parse(json['lastBackupAt']! as String),
  );
}
