import 'models.dart';

enum ConflictKind { missingRally, winner, score, setBoundary, roster }

class ReconciliationConflict {
  const ReconciliationConflict({
    required this.key,
    required this.kind,
    required this.message,
    this.primary,
    this.imported,
  });

  final String key;
  final ConflictKind kind;
  final String message;
  final Rally? primary;
  final Rally? imported;
}

class ReconciliationResult {
  const ReconciliationResult({
    required this.primary,
    required this.imported,
    required this.conflicts,
  });

  final ScorerLog primary;
  final ScorerLog imported;
  final List<ReconciliationConflict> conflicts;
}

class ReconciliationService {
  const ReconciliationService();

  ReconciliationResult compare(ScorerLog primary, ScorerLog imported) {
    if (primary.gameId != imported.gameId) {
      throw ArgumentError('Scorer logs belong to different games.');
    }
    final first = {
      for (final rally in primary.rallies) rally.alignmentKey: rally,
    };
    final second = {
      for (final rally in imported.rallies) rally.alignmentKey: rally,
    };
    final keys = <String>{...first.keys, ...second.keys}.toList()
      ..sort(_compareKeys);
    final conflicts = <ReconciliationConflict>[];
    for (final key in keys) {
      final a = first[key];
      final b = second[key];
      if (a == null || b == null) {
        conflicts.add(
          ReconciliationConflict(
            key: key,
            kind: ConflictKind.missingRally,
            message: 'Rally $key exists on only one scorer device.',
            primary: a,
            imported: b,
          ),
        );
      } else if (a.winnerTeamId != b.winnerTeamId) {
        conflicts.add(
          ReconciliationConflict(
            key: key,
            kind: ConflictKind.winner,
            message: 'The scorers selected different rally winners at $key.',
            primary: a,
            imported: b,
          ),
        );
      } else if (a.homeScore != b.homeScore || a.awayScore != b.awayScore) {
        conflicts.add(
          ReconciliationConflict(
            key: key,
            kind: ConflictKind.score,
            message: 'The score after rally $key does not match.',
            primary: a,
            imported: b,
          ),
        );
      }
    }
    return ReconciliationResult(
      primary: primary,
      imported: imported,
      conflicts: conflicts,
    );
  }

  ScorerLog merge(
    ReconciliationResult result, {
    required Set<String> preferImported,
    required String officialLogId,
    required DateTime now,
    Map<String, Rally> rallyOverrides = const {},
  }) {
    final first = {
      for (final rally in result.primary.rallies) rally.alignmentKey: rally,
    };
    final second = {
      for (final rally in result.imported.rallies) rally.alignmentKey: rally,
    };
    final keys = <String>{...first.keys, ...second.keys}.toList()
      ..sort(_compareKeys);
    final merged = <Rally>[];
    for (final key in keys) {
      final override = rallyOverrides[key];
      if (override != null) {
        merged.add(override);
        continue;
      }
      final chosen = preferImported.contains(key)
          ? (second[key] ?? first[key])
          : (first[key] ?? second[key]);
      if (chosen == null) continue;
      final other = identical(chosen, first[key]) ? second[key] : first[key];
      final actionById = <String, TeamAction>{
        for (final action in chosen.actions) action.id: action,
        for (final action in other?.actions ?? const <TeamAction>[])
          action.id: action,
      };
      merged.add(
        Rally(
          id: chosen.id,
          setNumber: chosen.setNumber,
          sequence: chosen.sequence,
          winnerTeamId: chosen.winnerTeamId,
          homeScore: chosen.homeScore,
          awayScore: chosen.awayScore,
          homeRotation: chosen.homeRotation,
          awayRotation: chosen.awayRotation,
          servingTeamId: chosen.servingTeamId,
          recordedAt: chosen.recordedAt,
          actions: actionById.values.toList(),
          overrideReason: chosen.overrideReason,
          correctionOf: chosen.correctionOf,
        ),
      );
    }
    return ScorerLog(
      id: officialLogId,
      gameId: result.primary.gameId,
      assignedTeamId: 'official',
      deviceId: result.primary.deviceId,
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: result.primary.initialServingTeamId,
      lineups: [...result.primary.lineups, ...result.imported.lineups],
      substitutions: {
        for (final item in result.primary.substitutions) item.id: item,
        for (final item in result.imported.substitutions) item.id: item,
      }.values.toList(),
      timeouts: {
        for (final item in result.primary.timeouts) item.id: item,
        for (final item in result.imported.timeouts) item.id: item,
      }.values.toList(),
      rotationAdjustments: {
        for (final item in result.primary.rotationAdjustments) item.id: item,
        for (final item in result.imported.rotationAdjustments) item.id: item,
      }.values.toList(),
      rallies: merged,
      corrections: [
        ...result.primary.corrections,
        ...result.imported.corrections,
      ],
    );
  }

  int _compareKeys(String a, String b) {
    final aa = a.split(':').map(int.parse).toList();
    final bb = b.split(':').map(int.parse).toList();
    final set = aa[0].compareTo(bb[0]);
    return set != 0 ? set : aa[1].compareTo(bb[1]);
  }
}
