import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vc_sets/application/offline_status.dart';
import 'package:vc_sets/presentation/widgets/offline_readiness.dart';

void main() {
  tearDown(() => offlineStatus.value = 'native');

  testWidgets('preparation and failure never advertise offline readiness', (
    tester,
  ) async {
    offlineStatus.value = 'preparing';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfflineReadiness())),
    );
    expect(find.text('Ready for offline use'), findsNothing);
    expect(
      find.textContaining('Keep this app open and connected'),
      findsOneWidget,
    );
    offlineStatus.value = 'failed';
    await tester.pump();
    expect(find.text('Ready for offline use'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    offlineStatus.value = 'ready';
    await tester.pump();
    expect(find.text('Ready for offline use'), findsOneWidget);
  });

  testWidgets('native apps have no web preparation status', (tester) async {
    offlineStatus.value = 'native';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OfflineReadiness())),
    );
    expect(find.byType(Text), findsNothing);
  });
}
