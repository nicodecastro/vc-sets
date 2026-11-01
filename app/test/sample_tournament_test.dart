import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/application/providers.dart';
import 'package:vc_sets/data/repository.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/reconciliation.dart';
import 'package:vc_sets/domain/sample_tournament.dart';
import 'package:vc_sets/domain/scoring.dart';
import 'package:vc_sets/domain/statistics.dart';

void main() {
  test(
    'sample loads once, preserves data, and persists valid results',
    () async {
      final existing = Tournament(
        id: 'existing',
        name: 'My tournament',
        venue: 'Gym',
        startsOn: DateTime.utc(2026),
        endsOn: DateTime.utc(2026),
        createdAt: DateTime.utc(2026),
      );
      final initial = AppData(deviceId: 'device', tournaments: [existing]);
      final repository = MemoryAppRepository(initial);
      final container = ProviderContainer(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(initial),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appControllerProvider.notifier);
      expect(await controller.loadSampleTournament(), sampleTournamentId);
      expect(await controller.loadSampleTournament(), sampleTournamentId);
      final saved = await repository.load();
      expect(saved.tournaments, hasLength(2));
      expect(saved.tournaments.first.id, existing.id);
      final tournament = AppData.decode(saved.encode()).tournaments.last;
      expect(tournament.id, sampleTournamentId);
      expect(tournament.teams, hasLength(4));
      expect(
        tournament.teams.every((team) => team.players.length == 7),
        isTrue,
      );
      expect(tournament.games, hasLength(6));
      expect(
        tournament.games.where((g) => g.status == GameStatus.finalized),
        hasLength(3),
      );
      expect(
        tournament.games.where((g) => g.status == GameStatus.scheduled),
        hasLength(1),
      );
      expect(
        tournament.games.where(
          (g) => g.status == GameStatus.awaitingReconciliation,
        ),
        hasLength(2),
      );
      for (final game in tournament.games) {
        final rules = tournament.rulesFor(game);
        expect(
          (
            rules.setsToWin,
            rules.maxSets,
            rules.regularSetTarget,
            rules.decidingSetTarget,
            rules.winBy,
          ),
          (2, 3, 25, 15, 2),
        );
        if (game.status == GameStatus.finalized) {
          final log = game.officialLog!;
          expect(
            const ScoringEngine().score(game, log, rules).isComplete,
            isTrue,
          );
          expect(
            const ScoringEngine().scoreProgressionReason(game, log),
            isNull,
          );
          expect(const ScoringEngine().excessRallyReason(log, rules), isNull);
          expect(game.logs, hasLength(2));
          final actions = log.rallies.expand((rally) => rally.actions).toList();
          for (final skill in [
            Skill.serve,
            Skill.reception,
            Skill.set,
            Skill.attack,
            Skill.block,
            Skill.dig,
            Skill.error,
            Skill.opponentError,
            Skill.teamFault,
          ]) {
            expect(
              actions.any((action) => action.skill == skill),
              isTrue,
              reason: '${game.id} lacks $skill',
            );
          }
          for (final rally in log.rallies) {
            final last = rally.actions.last;
            expect(
              const ScoringEngine().inferRallyWinner(game, last.teamId, [last]),
              rally.winnerTeamId,
            );
          }
          for (final scorerLog in game.logs) {
            expect(
              scorerLog.rallies
                  .expand((r) => r.actions)
                  .every((action) => action.teamId == scorerLog.assignedTeamId),
              isTrue,
            );
          }
          expect(
            const StatisticsService().gamePlayerStats(
              game,
              tournament.team(game.homeTeamId),
            ),
            isNotEmpty,
          );
        } else if (game.status == GameStatus.scheduled) {
          expect(game.logs, isEmpty);
        } else {
          expect(game.logs, hasLength(2));
          expect(game.officialLog, isNull);
          expect(game.revisions, isEmpty);
          for (final log in game.logs) {
            expect(
              log.rallies
                  .expand((r) => r.actions)
                  .every((action) => action.teamId == log.assignedTeamId),
              isTrue,
            );
          }
        }
      }
      const reconciliation = ReconciliationService();
      final practice = tournament.games[3];
      expect(tournament.team(practice.homeTeamId).name, 'Summit Six');
      expect(tournament.team(practice.awayTeamId).name, 'Metro Aces');
      final comparison = reconciliation.compare(
        practice.logs[0],
        practice.logs[1],
      );
      expect(comparison.conflicts, hasLength(6));
      for (final kind in [
        ConflictKind.missingRally,
        ConflictKind.winner,
        ConflictKind.score,
      ]) {
        expect(
          comparison.conflicts.where((conflict) => conflict.kind == kind),
          hasLength(2),
        );
      }
      final clean = tournament.games[4];
      expect(tournament.team(clean.homeTeamId).name, 'Harbor Spikers');
      expect(tournament.team(clean.awayTeamId).name, 'Metro Aces');
      expect(
        reconciliation.compare(clean.logs[0], clean.logs[1]).conflicts,
        isEmpty,
      );
      // Each of the three finalized matches contributes two team appearances.
      expect(
        const StatisticsService()
            .standings(tournament)
            .fold<int>(0, (total, row) => total + row.played),
        6,
      );
      for (final game in [practice, clean]) {
        await controller.finalizeReconciliation(
          tournament.id,
          game.id,
          preferImported: {},
          reason: 'Use the correct first scorer log',
        );
        final persisted = AppData.decode((await repository.load()).encode());
        final finalized = persisted.tournaments.last.games.firstWhere(
          (item) => item.id == game.id,
        );
        expect(finalized.status, GameStatus.finalized);
        expect(finalized.revisions, hasLength(1));
        final official = finalized.officialLog!;
        final rules = tournament.rulesFor(game);
        expect(
          const ScoringEngine().scoreProgressionReason(finalized, official),
          isNull,
        );
        expect(
          const ScoringEngine().excessRallyReason(official, rules),
          isNull,
        );
        expect(
          const ScoringEngine().score(finalized, official, rules).isComplete,
          isTrue,
        );
      }
      expect(
        const StatisticsService()
            .standings(tournament)
            .where((row) => row.played > 0),
        isNotEmpty,
      );
      await controller.refreshSampleTournament();
      final refreshed = await repository.load();
      expect(refreshed.tournaments, hasLength(2));
      expect(refreshed.tournaments.first.id, existing.id);
      expect(refreshed.tournaments.first.toJson(), existing.toJson());
      final refreshedSample = refreshed.tournaments.last;
      expect(refreshedSample.toJson(), buildSampleTournament().toJson());
      expect(
        refreshedSample.games.where(
          (game) => game.status == GameStatus.awaitingReconciliation,
        ),
        hasLength(2),
      );
      expect(
        refreshed.tournaments.last.games.first.officialLog!.rallies
            .expand((rally) => rally.actions)
            .length,
        greaterThan(100),
      );
    },
  );
}
