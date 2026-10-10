import 'package:vc_sets/domain/models.dart';

final homeTeam = TournamentTeam(
  id: 'home',
  name: 'Home Club',
  shortCode: 'HOM',
  colorValue: 0xFF006C67,
  players: List.generate(
    6,
    (index) => Player(
      id: 'home-$index',
      number: index + 1,
      name: 'Home ${index + 1}',
      position: index == 5 ? PlayerPosition.L : PlayerPosition.U,
    ),
  ),
);

final awayTeam = TournamentTeam(
  id: 'away',
  name: 'Away Club',
  shortCode: 'AWY',
  colorValue: 0xFFAA4400,
  players: List.generate(
    6,
    (index) => Player(
      id: 'away-$index',
      number: index + 7,
      name: 'Away ${index + 1}',
      position: PlayerPosition.U,
    ),
  ),
);

Game testGame({List<ScorerLog> logs = const [], ScorerLog? officialLog}) =>
    Game(
      id: 'game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: DateTime.utc(2026, 10, 2),
      venue: 'Main Court',
      logs: logs,
      officialLog: officialLog,
      status: officialLog == null
          ? GameStatus.inProgress
          : GameStatus.finalized,
    );

ScorerLog testLog({
  String id = 'log-a',
  String assignedTeamId = 'home',
  String deviceId = 'device-a',
  List<Rally> rallies = const [],
}) => ScorerLog(
  id: id,
  gameId: 'game',
  assignedTeamId: assignedTeamId,
  deviceId: deviceId,
  createdAt: DateTime.utc(2026, 10, 2),
  updatedAt: DateTime.utc(2026, 10, 2),
  initialServingTeamId: homeTeam.id,
  rallies: rallies,
);

Tournament testTournament({List<Game> games = const []}) => Tournament(
  id: 'tournament',
  name: 'Club Cup',
  venue: 'Main Court',
  startsOn: DateTime.utc(2026, 10, 2),
  endsOn: DateTime.utc(2026, 10, 2),
  createdAt: DateTime.utc(2026, 9, 1),
  teams: [homeTeam, awayTeam],
  games: games,
);
