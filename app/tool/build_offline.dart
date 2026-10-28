import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

// Run after flutter build web, from app/.
Future<void> main(List<String> arguments) async {
  final output = Directory(arguments.isEmpty ? 'build/web' : arguments.single);
  final bootstrap = File('${output.path}/flutter_bootstrap.js');
  final original = await bootstrap.readAsString();
  if (!original.contains('__VC_SETS_BUILD__')) {
    throw StateError(
      'Build a fresh web release before generating offline files.',
    );
  }
  final files = await output
      .list(recursive: true)
      .where((entry) {
        final name = entry.uri.pathSegments.last;
        return entry is File &&
            !name.startsWith('.') &&
            !name.endsWith('.map') &&
            name != 'flutter_service_worker.js';
      })
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  final hashes = <String, String>{};
  for (final file in files) {
    final relative = path
        .relative(file.path, from: output.path)
        .replaceAll('\\', '/');
    hashes[relative] = sha256.convert(await file.readAsBytes()).toString();
  }
  final template = await File('tool/offline_worker.js').readAsString();
  final version = sha256
      .convert(utf8.encode('${jsonEncode(hashes)}$template'))
      .toString();
  await bootstrap.writeAsString(
    original.replaceAll('__VC_SETS_BUILD__', version),
  );
  hashes['flutter_bootstrap.js'] = sha256
      .convert(await bootstrap.readAsBytes())
      .toString();
  await File('${output.path}/flutter_service_worker.js').writeAsString(
    'const VERSION = ${jsonEncode(version)};\n'
    'const ASSETS = ${jsonEncode(hashes)};\n$template',
  );
  stdout.writeln('Offline release $version: ${hashes.length} verified files.');
}
