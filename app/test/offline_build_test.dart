import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/build_offline.dart' as builder;

void main() {
  test(
    'offline build hashes final bootstrap and excludes itself and debug files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vc-sets-offline-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/flutter_bootstrap.js')
          .writeAsString('const release = "__VC_SETS_BUILD__";');
      await File('${directory.path}/sqlite3.wasm').writeAsBytes([0, 1, 2]);
      await File('${directory.path}/flutter_service_worker.js')
          .writeAsString('old cleanup stub');
      await File('${directory.path}/debug.map').writeAsString('debug');
      await File('${directory.path}/.last_build_id').writeAsString('metadata');
      await builder.main([directory.path]);
      final worker = await File('${directory.path}/flutter_service_worker.js')
          .readAsString();
      final assets = jsonDecode(
        RegExp(r'const ASSETS = (.*);').firstMatch(worker)!.group(1)!,
      ) as Map;
      expect(
        assets.keys,
        unorderedEquals(['flutter_bootstrap.js', 'sqlite3.wasm']),
      );
      final bootstrap = await File('${directory.path}/flutter_bootstrap.js')
          .readAsString();
      expect(bootstrap, isNot(contains('__VC_SETS_BUILD__')));
      expect(
        assets['flutter_bootstrap.js'],
        sha256.convert(utf8.encode(bootstrap)).toString(),
      );
      final version = jsonDecode(
        RegExp(r'const VERSION = (.*);').firstMatch(worker)!.group(1)!,
      );
      expect(bootstrap, contains(version as String));
      await expectLater(builder.main([directory.path]), throwsStateError);
    },
  );
}
