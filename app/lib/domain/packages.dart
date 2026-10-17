import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';

class PackageManifest {
  const PackageManifest({
    required this.schemaVersion,
    required this.packageId,
    required this.type,
    required this.sourceDeviceId,
    required this.exportedAt,
    required this.payloadSha256,
  });
  final int schemaVersion;
  final String packageId;
  final String type;
  final String sourceDeviceId;
  final DateTime exportedAt;
  final String payloadSha256;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'packageId': packageId,
    'type': type,
    'sourceDeviceId': sourceDeviceId,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'payloadSha256': payloadSha256,
  };

  factory PackageManifest.fromJson(Map<String, Object?> json) =>
      PackageManifest(
        schemaVersion: (json['schemaVersion'] as num).toInt(),
        packageId: json['packageId']! as String,
        type: json['type']! as String,
        sourceDeviceId: json['sourceDeviceId']! as String,
        exportedAt: DateTime.parse(json['exportedAt']! as String),
        payloadSha256: json['payloadSha256']! as String,
      );
}

class GamePackage {
  const GamePackage({
    required this.manifest,
    required this.tournament,
    required this.gameId,
    this.log,
  });
  final PackageManifest manifest;
  final Tournament tournament;
  final String gameId;
  final ScorerLog? log;

  Map<String, Object?> get payload => {
    'tournament': tournament.toJson(),
    'gameId': gameId,
    'log': log?.toJson(),
  };
  Map<String, Object?> toJson() => {
    'manifest': manifest.toJson(),
    'payload': payload,
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class PortablePackageService {
  const PortablePackageService();
  static const schemaVersion = 5;

  GamePackage createGamePackage({
    required String packageId,
    required String deviceId,
    required DateTime exportedAt,
    required Tournament tournament,
    required Game game,
    ScorerLog? log,
  }) {
    final snapshot = tournament.copyWith(
      games: [game.copyWith(logs: const [], clearOfficialLog: true)],
    );
    final payload = {
      'tournament': snapshot.toJson(),
      'gameId': game.id,
      'log': log?.toJson(),
    };
    return GamePackage(
      manifest: _manifest(packageId, 'game', deviceId, exportedAt, payload),
      tournament: snapshot,
      gameId: game.id,
      log: log,
    );
  }

  GamePackage decodeGamePackage(String source) {
    final root = (jsonDecode(source) as Map).cast<String, Object?>();
    final manifest = PackageManifest.fromJson(
      (root['manifest']! as Map).cast<String, Object?>(),
    );
    final payload = (root['payload']! as Map).cast<String, Object?>();
    _validate(manifest, payload, 'game', source);
    return GamePackage(
      manifest: manifest,
      tournament: Tournament.fromJson(
        (payload['tournament']! as Map).cast<String, Object?>(),
      ),
      gameId: payload['gameId']! as String,
      log: payload['log'] == null
          ? null
          : ScorerLog.fromJson(
              (payload['log']! as Map).cast<String, Object?>(),
            ),
    );
  }

  String createBackup({
    required String packageId,
    required AppData data,
    required DateTime exportedAt,
  }) {
    final payload = data.toJson();
    final root = {
      'manifest': _manifest(
        packageId,
        'backup',
        data.deviceId,
        exportedAt,
        payload,
      ).toJson(),
      'payload': payload,
    };
    return const JsonEncoder.withIndent('  ').convert(root);
  }

  AppData decodeBackup(String source, {bool verifyIntegrity = true}) {
    final root = (jsonDecode(source) as Map).cast<String, Object?>();
    final manifest = PackageManifest.fromJson(
      (root['manifest']! as Map).cast<String, Object?>(),
    );
    final payload = (root['payload']! as Map).cast<String, Object?>();
    _validate(
      manifest,
      payload,
      'backup',
      source,
      verifyIntegrity: verifyIntegrity,
    );
    return AppData.fromJson(payload);
  }

  PackageManifest _manifest(
    String id,
    String type,
    String deviceId,
    DateTime exportedAt,
    Map<String, Object?> payload,
  ) => PackageManifest(
    schemaVersion: schemaVersion,
    packageId: id,
    type: type,
    sourceDeviceId: deviceId,
    exportedAt: exportedAt,
    payloadSha256: sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
  );

  void _validate(
    PackageManifest manifest,
    Map<String, Object?> payload,
    String expectedType,
    String source, {
    bool verifyIntegrity = true,
  }) {
    if (manifest.schemaVersion > schemaVersion) {
      throw const FormatException(
        'This package was created by a newer VC SETS version.',
      );
    }
    if (manifest.type != expectedType) {
      throw const FormatException('Unexpected package type.');
    }
    if (!verifyIntegrity) return;
    // Hash the exporter's key order first; web JSON parsing can reorder keys.
    final serialized = _compactPayload(source);
    final originalDigest = sha256.convert(utf8.encode(serialized)).toString();
    if (originalDigest == manifest.payloadSha256) return;

    final decodedDigest = sha256.convert(utf8.encode(jsonEncode(payload)));
    if (decodedDigest.toString() != manifest.payloadSha256) {
      throw const FormatException('Package integrity check failed.');
    }
  }

  String _compactPayload(String source) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    var stringStart = 0;
    int? payloadStart;
    int? payloadEnd;
    int? segmentStart;
    final result = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      final char = source.codeUnitAt(index);
      if (payloadStart != null && payloadEnd == null && index >= payloadStart) {
        if (inString || !_isJsonSpace(char)) {
          segmentStart ??= index;
        } else if (segmentStart != null) {
          result.write(source.substring(segmentStart, index));
          segmentStart = null;
        }
      }
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == 0x5c) {
          escaped = true;
        } else if (char == 0x22) {
          inString = false;
          if (depth != 1) continue;
          var next = index + 1;
          while (next < source.length &&
              _isJsonSpace(source.codeUnitAt(next))) {
            next++;
          }
          if (next >= source.length || source.codeUnitAt(next) != 0x3a) {
            continue;
          }
          if (jsonDecode(source.substring(stringStart, index + 1)) !=
              'payload') {
            continue;
          }
          if (payloadStart != null) {
            throw const FormatException('Duplicate package payload.');
          }
          next++;
          while (next < source.length &&
              _isJsonSpace(source.codeUnitAt(next))) {
            next++;
          }
          if (next >= source.length || source.codeUnitAt(next) != 0x7b) {
            throw const FormatException('Invalid package payload.');
          }
          payloadStart = next;
        }
        continue;
      }
      if (char == 0x22) {
        inString = true;
        stringStart = index;
      } else if (char == 0x7b || char == 0x5b) {
        depth++;
      } else if (char == 0x7d || char == 0x5d) {
        if (char == 0x7d &&
            depth == 2 &&
            payloadStart != null &&
            payloadEnd == null) {
          payloadEnd = index + 1;
        }
        depth--;
      }
    }
    if (payloadStart == null || payloadEnd == null) {
      throw const FormatException('Invalid package payload.');
    }
    if (segmentStart != null) {
      result.write(source.substring(segmentStart, payloadEnd));
    }
    return result.toString();
  }

  bool _isJsonSpace(int char) =>
      char == 0x20 || char == 0x09 || char == 0x0a || char == 0x0d;
}
