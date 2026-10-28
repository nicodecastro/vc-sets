import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await AppDatabase.open();
  final repository = DriftAppRepository(database);
  final initialData = await repository.load();
  runApp(
    ProviderScope(
      overrides: [
        appRepositoryProvider.overrideWithValue(repository),
        initialAppDataProvider.overrideWithValue(initialData),
      ],
      child: VcSetsApp(),
    ),
  );
}
