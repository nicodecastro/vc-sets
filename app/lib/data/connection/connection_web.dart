import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

bool hasPersistentWebStorage = false;

Future<QueryExecutor> openConnection() async {
  final result = await WasmDatabase.open(
    databaseName: 'vc_sets',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  hasPersistentWebStorage =
      result.chosenImplementation != WasmStorageImplementation.inMemory;
  return result.resolvedExecutor;
}
