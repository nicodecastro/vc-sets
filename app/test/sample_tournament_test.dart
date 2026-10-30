import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/application/providers.dart';
import 'package:vc_sets/data/repository.dart';
import 'package:vc_sets/domain/models.dart';
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
        hasLength(3),
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
        } else {
          expect(game.logs, isEmpty);
        }
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
      expect(
        refreshed.tournaments.last.games.first.officialLog!.rallies
            .expand((rally) => rally.actions)
            .length,
        greaterThan(100),
      );
    },
  );
}
