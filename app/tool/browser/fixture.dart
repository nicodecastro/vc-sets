import 'dart:io';

import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/domain/packages.dart';

import '../../test/test_fixtures.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27);
  final lineup = LineupSnapshot(
    teamId: homeTeam.id,
    playerIds: homeTeam.players.map((player) => player.id).toList(),
    setNumber: 1,
  );
  final log = testLog().copyWith(lineups: [lineup]);
  final official = ScorerLog(
    id: 'official',
    gameId: 'finalized-game',
    assignedTeamId: homeTeam.id,
    deviceId: 'browser-fixture',
    createdAt: now,
    updatedAt: now,
    initialServingTeamId: homeTeam.id,
    rallies: [
      Rally(
        id: 'official-rally',
        setNumber: 1,
        sequence: 1,
        winnerTeamId: homeTeam.id,
        homeScore: 1,
        awayScore: 0,
        homeRotation: 1,
        awayRotation: 1,
        servingTeamId: homeTeam.id,
        recordedAt: now,
        actions: [
          TeamAction(
            id: 'ace',
            teamId: homeTeam.id,
            playerId: homeTeam.players.first.id,
            skill: Skill.serve,
            grade: ActionGrade.success,
            recordedAt: now,
          ),
        ],
      ),
    ],
  );
  final completed = Game(
    id: 'finalized-game',
    tournamentId: 'tournament',
    homeTeamId: homeTeam.id,
    awayTeamId: awayTeam.id,
    scheduledAt: now,
    venue: 'Main Court',
    status: GameStatus.finalized,
    officialLog: official,
    rulesSnapshot: const MatchRules(
      setsToWin: 1,
      maxSets: 1,
      regularSetTarget: 1,
      winBy: 1,
    ),
  );
  final data = AppData(
    deviceId: 'browser-fixture',
    tournaments: [
      testTournament(
        games: [
          testGame(logs: [log]),
          completed,
        ],
      ),
    ],
  );
  File('tool/browser/fixture.vcbackup').writeAsStringSync(
    const PortablePackageService().createBackup(
      packageId: 'browser-backup',
      data: data,
      exportedAt: now,
    ),
  );
}
