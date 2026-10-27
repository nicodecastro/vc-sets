import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/packages.dart';
import '../domain/statistics.dart';
import 'file_picker_options.dart'
    if (dart.library.js_interop) 'file_picker_options_web.dart'
    as picker_options;

class FileExchangeService {
  const FileExchangeService();

  Future<void> exportGame(
    AppData data,
    Tournament tournament,
    Game game,
    ScorerLog? log,
  ) async {
    final package = const PortablePackageService().createGamePackage(
      packageId: const Uuid().v4(),
      deviceId: data.deviceId,
      exportedAt: DateTime.now(),
      tournament: tournament,
      game: game,
      log: log,
    );
    await _save(
      '${_safe(tournament.name)}-${game.id.substring(0, 8)}.vcgame',
      package.encode(),
    );
  }

  Future<GamePackage?> pickGamePackage() async {
    final bytes = await _pickPortableFile('Import VC SETS game package');
    if (bytes == null) return null;
    return decodeGamePackageBytes(bytes);
  }

  GamePackage decodeGamePackageBytes(Uint8List bytes) =>
      const PortablePackageService().decodeGamePackage(
        _decodePortableText(bytes),
      );

  Future<void> exportBackup(AppData data) async {
    final now = DateTime.now();
    final content = const PortablePackageService().createBackup(
      packageId: const Uuid().v4(),
      data: data,
      exportedAt: now,
    );
    await _save(
      'vc-sets-backup-${DateFormat('yyyy-MM-dd-HHmm').format(now)}.vcbackup',
      content,
    );
  }

  Future<AppData?> pickBackup({bool verifyIntegrity = true}) async {
    final bytes = await _pickPortableFile('Restore VC SETS backup');
    if (bytes == null) return null;
    return decodeBackupBytes(bytes, verifyIntegrity: verifyIntegrity);
  }

  AppData decodeBackupBytes(Uint8List bytes, {bool verifyIntegrity = true}) =>
      const PortablePackageService().decodeBackup(
        _decodePortableText(bytes),
        verifyIntegrity: verifyIntegrity,
      );

  Future<void> exportStandingsCsv(Tournament tournament) async {
    final buffer = StringBuffer(
      'Pool,Rank,Team,Played,Wins,Losses,Match points,Sets won,Sets lost,Points won,Points lost\r\n',
    );
    final pools = tournament.format == TournamentFormat.poolsThenKnockout
        ? List.generate(tournament.poolCount, (index) => index + 1)
        : const <int?>[null];
    for (final pool in pools) {
      final rows = const StatisticsService().standings(
        tournament,
        poolNumber: pool,
      );
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        buffer.writeln(
          '${pool == null ? '' : _poolLabel(pool)},${index + 1},${_csv(row.team.name)},${row.played},${row.wins},${row.losses},${row.matchPoints},${row.setsWon},${row.setsLost},${row.pointsWon},${row.pointsLost}',
        );
      }
    }
    await _save(
      '${_safe(tournament.name)}-standings.csv',
      buffer.toString(),
      mime: 'text/csv',
    );
  }

  Future<void> exportPlayersCsv(Tournament tournament) async {
    await _save(
      '${_safe(tournament.name)}-player-stats.csv',
      playerStatsCsv(tournament),
      mime: 'text/csv',
    );
  }

  String playerStatsCsv(Tournament tournament) {
    final rows = const StatisticsService().playerStatsSummary(tournament);
    final buffer = StringBuffer(
      'Team,Last name,Number,${playerStatColumns.join(',')},Games played,Sets played,Games won\r\n',
    );
    for (final row in rows) {
      buffer.writeln(
        '${_csv(row.team.name)},${_csv(row.lastName)},${row.player.number},${playerStatColumns.map((column) => row.counts[column] ?? 0).join(',')},${row.gamesPlayed},${row.setsPlayed},${row.gamesWon}',
      );
    }
    return buffer.toString();
  }

  Future<void> exportR5AndSubsCsv(Tournament tournament) async {
    await _save(
      '${_safe(tournament.name)}-r5-subs.csv',
      r5AndSubsCsv(tournament),
      mime: 'text/csv',
    );
  }

  String r5AndSubsCsv(Tournament tournament) {
    final buffer = StringBuffer(
      'Game ID,Scheduled (UTC),Home,Away,Team,Set,Entry,Recorded (UTC),Rotation,I,II,III,IV,V,VI,Player out,Player in,Home score,Away score,Sub type,Automatic\r\n',
    );
    void writeRow(List<Object?> values) => buffer.writeln(
      values
          .map((value) {
            if (value == null) return '';
            return value is String ? _csv(value) : '$value';
          })
          .join(','),
    );

    final games = [...tournament.games]
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    for (final game in games) {
      final home = tournament.team(game.homeTeamId);
      final away = tournament.team(game.awayTeamId);
      final logs =
          game.status == GameStatus.finalized && game.officialLog != null
          ? [game.officialLog!]
          : game.logs;
      for (final team in [home, away]) {
        final players = {for (final player in team.players) player.id: player};
        String playerLabel(String id) {
          final player = players[id];
          return player == null ? id : '#${player.number} ${player.name}';
        }

        final lineups =
            [
              for (final log in logs)
                ...log.lineups.where((item) => item.teamId == team.id),
            ]..sort((a, b) {
              final set = a.setNumber.compareTo(b.setNumber);
              return set != 0
                  ? set
                  : (a.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                        .compareTo(
                          b.recordedAt ??
                              DateTime.fromMillisecondsSinceEpoch(0),
                        );
            });
        final substitutions =
            [
              for (final log in logs)
                ...log.substitutions.where((item) => item.teamId == team.id),
            ]..sort((a, b) {
              final set = a.setNumber.compareTo(b.setNumber);
              return set != 0 ? set : a.recordedAt.compareTo(b.recordedAt);
            });
        final sets = {
          ...lineups.map((item) => item.setNumber),
          ...substitutions.map((item) => item.setNumber),
        }.toList()..sort();
        final gameColumns = <Object?>[
          game.id,
          game.scheduledAt.toUtc().toIso8601String(),
          home.name,
          away.name,
          team.name,
        ];
        for (final set in sets) {
          for (final lineup in lineups.where((item) => item.setNumber == set)) {
            writeRow([
              ...gameColumns,
              set,
              'R-5',
              lineup.recordedAt?.toUtc().toIso8601String() ?? '',
              lineup.rotation,
              for (var position = 0; position < 6; position++)
                position < lineup.playerIds.length
                    ? playerLabel(lineup.playerIds[position])
                    : '',
              '',
              '',
              null,
              null,
              '',
              '',
            ]);
          }
          for (final substitution in substitutions.where(
            (item) => item.setNumber == set,
          )) {
            writeRow([
              ...gameColumns,
              set,
              'Sub',
              substitution.recordedAt.toUtc().toIso8601String(),
              null,
              ...List.filled(6, ''),
              playerLabel(substitution.playerOutId),
              playerLabel(substitution.playerInId),
              substitution.homeScore,
              substitution.awayScore,
              substitution.isLiberoReplacement
                  ? 'Libero replacement'
                  : 'Regular',
              substitution.automaticAfterEventId == null ? 'No' : 'Yes',
            ]);
          }
        }
      }
    }
    return buffer.toString();
  }

  Future<void> exportPrintableHtml(Tournament tournament) async {
    final pools = tournament.format == TournamentFormat.poolsThenKnockout
        ? List.generate(tournament.poolCount, (index) => index + 1)
        : const <int?>[null];
    final standingsHtml = pools.map((pool) {
      final standings = const StatisticsService().standings(
        tournament,
        poolNumber: pool,
      );
      final heading = pool == null ? 'Standings' : 'Pool ${_poolLabel(pool)}';
      return '''<h2>$heading</h2><table><thead><tr><th>#</th><th>Team</th><th>P</th><th>W</th><th>L</th><th>Pts</th><th>Sets</th><th>Points</th></tr></thead><tbody>
${[for (var i = 0; i < standings.length; i++) '<tr><td>${i + 1}</td><td>${_html(standings[i].team.name)}</td><td>${standings[i].played}</td><td>${standings[i].wins}</td><td>${standings[i].losses}</td><td>${standings[i].matchPoints}</td><td>${standings[i].setsWon}-${standings[i].setsLost}</td><td>${standings[i].pointsWon}-${standings[i].pointsLost}</td></tr>'].join()}
</tbody></table>''';
    }).join();
    final playerStats = const StatisticsService().playerStatsSummary(
      tournament,
    );
    final playerHeader = [
      'Team',
      'Last name',
      '#',
      ...playerStatColumns,
      'Games played',
      'Sets played',
      'Games won',
    ].map((column) => '<th>${_html(column)}</th>').join();
    final playerRows = playerStats
        .map(
          (row) =>
              '<tr><td>${_html(row.team.name)}</td><td>${_html(row.lastName)}</td><td>${row.player.number}</td>${playerStatColumns.map((column) => '<td>${row.counts[column] ?? 0}</td>').join()}<td>${row.gamesPlayed}</td><td>${row.setsPlayed}</td><td>${row.gamesWon}</td></tr>',
        )
        .join();
    final html =
        '''<!doctype html>
<html><head><meta charset="utf-8"><title>${_html(tournament.name)} report</title>
<style>
body{font-family:system-ui,sans-serif;margin:32px;color:#17332f}h1{margin-bottom:4px}h2{margin-top:32px}
table{width:100%;border-collapse:collapse;margin-top:12px}th,td{padding:8px;border-bottom:1px solid #ccd8d4;text-align:left}
th{background:#e5f1ed}.player-stats{font-size:9px}.player-stats th,.player-stats td{padding:4px}@media print{body{margin:8mm}.no-print{display:none}@page{size:landscape}}
</style></head><body>
<button class="no-print" onclick="window.print()">Print report</button>
<h1>${_html(tournament.name)}</h1><div>${_html(tournament.venue)} • Generated ${DateFormat.yMMMd().add_jm().format(DateTime.now())}</div>
$standingsHtml<h2>Player stats summary</h2><table class="player-stats"><thead><tr>$playerHeader</tr></thead><tbody>
$playerRows
</tbody></table></body></html>''';
    await _save(
      '${_safe(tournament.name)}-print-report.html',
      html,
      mime: 'text/html',
    );
  }

  Future<void> _save(
    String fileName,
    String source, {
    String mime = 'application/json',
  }) async {
    await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(source)),
      mimeType: mime,
    );
  }

  Future<Uint8List?> _pickPortableFile(String dialogTitle) async {
    // Do not apply an extension filter: iOS Files disables unknown custom
    // extensions such as .vcbackup and .vcgame when an accept filter exists.
    // On web, preload bytes and do not cancel when the iOS Files sheet causes
    // Safari/PWA to lose focus.
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.any,
      webOptions: picker_options.portableImportWebOptions(),
    );
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const FormatException('The selected file is empty.');
      }
      return bytes;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw StateError(
        'The selected file could not be read. On iPhone or iPad, save it in the Files app first, then select it from On My iPhone or iCloud Drive.',
      );
    }
  }

  String _decodePortableText(Uint8List bytes) {
    var source = utf8.decode(bytes);
    if (source.startsWith('\uFEFF')) source = source.substring(1);
    return source;
  }

  String _safe(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  String _csv(String value) => '"${value.replaceAll('"', '""')}"';
  String _poolLabel(int pool) =>
      String.fromCharCode('A'.codeUnitAt(0) + pool - 1);
  String _html(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
