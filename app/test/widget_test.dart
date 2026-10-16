import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:vc_sets/application/providers.dart';
import 'package:vc_sets/data/repository.dart';
import 'package:vc_sets/domain/models.dart';
import 'package:vc_sets/presentation/app.dart';
import 'package:vc_sets/presentation/pages/games_page.dart';
import 'package:vc_sets/presentation/pages/reconcile_page.dart';
import 'package:vc_sets/presentation/pages/reports_page.dart';
import 'package:vc_sets/presentation/pages/tournament_detail_page.dart';
import 'package:vc_sets/presentation/pages/tracker_page.dart';

import 'test_fixtures.dart';

void main() {
  testWidgets('dashboard renders at phone and desktop widths', (tester) async {
    const data = AppData(deviceId: 'test-device');
    final repository = MemoryAppRepository(data);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: VcSetsApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Match day, under control'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('tracker renders R-5 court player buttons and team controls', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 2);
    final log = ScorerLog(
      id: 'log',
      gameId: 'game',
      assignedTeamId: homeTeam.id,
      deviceId: 'test-device',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: homeTeam.id,
      timeouts: [
        TeamTimeout(
          id: 'timeout',
          teamId: homeTeam.id,
          setNumber: 1,
          homeScore: 0,
          awayScore: 0,
          recordedAt: DateTime(2026, 10, 2, 14, 37),
        ),
      ],
      lineups: [
        LineupSnapshot(
          teamId: homeTeam.id,
          playerIds: homeTeam.players
              .take(6)
              .map((player) => player.id)
              .toList(),
          recordedAt: now,
        ),
      ],
    );
    final game = Game(
      id: 'game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: now,
      venue: 'Gym',
      status: GameStatus.inProgress,
      logs: [log],
    );
    final tournament = Tournament(
      id: 'tournament',
      name: 'League',
      venue: 'Gym',
      startsOn: now,
      endsOn: now,
      createdAt: now,
      teams: [homeTeam, awayTeam],
      games: [game],
    );
    final data = AppData(deviceId: 'test-device', tournaments: [tournament]);
    final repository = MemoryAppRepository(data);
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: const MaterialApp(
          home: TrackerPage(tournamentId: 'tournament', gameId: 'game'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NET • FRONT ROW'), findsOneWidget);
    expect(find.text('R-5 • Set 1'), findsOneWidget);
    expect(find.text('Subs (0)'), findsOneWidget);
    expect(find.text('Timeout (1/2)'), findsOneWidget);
    expect(find.text('Libero'), findsOneWidget);
    expect(find.text('Quick swap'), findsOneWidget);
    final r5Center = tester.getCenter(find.text('R-5 • Set 1'));
    final subsCenter = tester.getCenter(find.text('Subs (0)'));
    final timeoutCenter = tester.getCenter(find.text('Timeout (1/2)'));
    final liberoCenter = tester.getCenter(
      find.ancestor(
        of: find.text('Libero'),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );
    final quickSwapCenter = tester.getCenter(
      find.ancestor(
        of: find.text('Quick swap'),
        matching: find.byType(FilledButton),
      ),
    );
    final rotationCenter = tester.getCenter(
      find.ancestor(
        of: find.text('Rotation 1').first,
        matching: find.byType(Chip),
      ),
    );
    expect(r5Center.dy, subsCenter.dy);
    expect(r5Center.dy, timeoutCenter.dy);
    expect(liberoCenter.dy, quickSwapCenter.dy);
    expect(liberoCenter.dy, rotationCenter.dy);
    expect(liberoCenter.dy, greaterThan(r5Center.dy));
    expect(r5Center.dx, lessThan(subsCenter.dx));
    expect(subsCenter.dx, lessThan(timeoutCenter.dx));
    expect(liberoCenter.dx, lessThan(quickSwapCenter.dx));
    expect(quickSwapCenter.dx, lessThan(rotationCenter.dx));
    expect(find.text('Enter'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: find.text('Enter'),
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    expect(find.text('#1'), findsWidgets);
    expect(find.text('ATT'), findsNWidgets(6));
    expect(find.text('EXC'), findsNWidgets(6));
    expect(find.text('ERR'), findsNWidgets(6));
    expect(find.text('OPP ERR  •  OP+'), findsOneWidget);
    expect(find.text('TEAM FAULT  •  T-'), findsOneWidget);
    final opponentErrorCenter = tester.getCenter(find.text('OPP ERR  •  OP+'));
    final teamFaultCenter = tester.getCenter(find.text('TEAM FAULT  •  T-'));
    final enterCenter = tester.getCenter(find.text('Enter'));
    expect(enterCenter.dy, opponentErrorCenter.dy);
    expect(enterCenter.dy, teamFaultCenter.dy);
    expect(enterCenter.dx, greaterThan(teamFaultCenter.dx));
    expect(find.text('Home 4'), findsOneWidget);
    expect(find.text('U • IV'), findsOneWidget);
    expect(find.text('Tap a team panel to award the next rally'), findsNothing);
    expect(
      find.ancestor(of: find.text('HOM'), matching: find.byType(InkWell)),
      findsNothing,
    );
    expect(find.text('V1'), findsOneWidget);
    expect(find.text('Selected: #1 Home 1'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpAndSettle();
    expect(find.text('Quick swap'), findsOneWidget);
    final scoreboard = tester.getTopLeft(find.text('SET 1'));
    final timeline = tester.getTopLeft(find.text('Event timeline'));
    final playerActions = tester.getTopLeft(find.text('Player actions'));
    expect(
      find.text(
        'Set 1 • 0-0 • ${DateFormat.jm().format(DateTime(2026, 10, 2, 14, 37))}',
      ),
      findsOneWidget,
    );
    final desktopAttButton = find
        .ancestor(
          of: find.text('ATT').first,
          matching: find.byType(OutlinedButton),
        )
        .first;
    expect(scoreboard.dy, lessThan(timeline.dy));
    expect(playerActions.dy, lessThan(160));
    expect(tester.getSize(desktopAttButton).height, lessThanOrEqualTo(34));
    expect(find.byKey(const ValueKey('timeline-draft-header')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-draft-skill-0')),
        matching: find.text('V1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('EXC').first);
    await tester.pump();
    expect(find.text('V1'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-draft-skill-0')),
        matching: find.text('V1+'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: find.text('Enter'),
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Enter'));
    await tester.pumpAndSettle();
    expect(find.text('HOM point  •  1-0'), findsOneWidget);
    expect(find.text('Set 1 • V1+'), findsOneWidget);
    expect(find.text('V1'), findsNWidgets(2));

    await tester.tap(find.text('EXC').first);
    await tester.pump();
    expect(find.text('V1+'), findsNWidgets(2));

    await tester.ensureVisible(find.text('OPP ERR  •  OP+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OPP ERR  •  OP+'));
    await tester.ensureVisible(find.text('TEAM FAULT  •  T-'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEAM FAULT  •  T-'));
    await tester.pump();
    for (final (index, skill) in ['T-', 'OP+', 'V1+'].indexed) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('timeline-draft-skill-$index')),
          matching: find.text(skill),
        ),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-draft-skill-0')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();
    expect(find.text('T-'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-draft-skill-0')),
        matching: find.text('OP+'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('TEAM FAULT  •  T-'));
    await tester.pump();

    for (final size in [const Size(810, 1080), const Size(1080, 810)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpAndSettle();
      expect(find.text('Quick swap'), findsOneWidget);
      final entryScroll = find.byKey(const ValueKey('tracker-entry-scroll'));
      expect(entryScroll, findsOneWidget);
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(of: entryScroll, matching: find.byType(Scrollable))
            .first,
      );
      expect(
        scrollable.position.maxScrollExtent,
        0,
        reason:
            'Player actions and a populated rally should fit without scrolling at $size.',
      );
      expect(find.text('Event timeline'), findsOneWidget);
      expect(find.text('TEAM FAULT  •  T-'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.text('Enter'));
    await tester.pumpAndSettle();
    expect(find.text('AWY point  •  1-1'), findsOneWidget);
    expect(find.text('T-'), findsNothing);
    expect(find.text('This rally'), findsNothing);
    expect(find.byKey(const ValueKey('timeline-draft-header')), findsNothing);

    await tester.tap(find.text('OPP ERR  •  OP+'));
    await tester.pump();
    await tester.tap(find.text('Enter'));
    await tester.pumpAndSettle();
    expect(find.text('HOM point  •  2-1'), findsOneWidget);
    expect(find.text('V2'), findsNWidgets(2));
    expect(find.text('Selected: #2 Home 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Manually rotate lineup'));
    await tester.pumpAndSettle();
    expect(find.text('Manually rotate lineup?'), findsOneWidget);
    await tester.tap(find.text('Rotate'));
    await tester.pumpAndSettle();
    expect(find.text('HOM manually rotated to 3'), findsOneWidget);
    expect(find.text('Selected: #3 Home 3'), findsOneWidget);
  });

  testWidgets('empty R-5 blocks scoring until six players are saved', (
    tester,
  ) async {
    final log = testLog(deviceId: 'test-device');
    final game = testGame(logs: [log]);
    final data = AppData(
      deviceId: 'test-device',
      tournaments: [
        testTournament(games: [game]),
      ],
    );
    final repository = MemoryAppRepository(data);
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: const MaterialApp(
          home: TrackerPage(tournamentId: 'tournament', gameId: 'game'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Set 1 lineup required. Tap R-5 to enable scoring.'),
      findsOneWidget,
    );
    expect(find.text('Empty'), findsNWidgets(6));
    expect(find.text('V1'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find
                .ancestor(
                  of: find.text('ATT').first,
                  matching: find.byType(OutlinedButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: find.text('Enter'),
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('R-5 • Set 1'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to select'), findsNWidgets(6));
    expect(
      tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: find.text('Save lineup'),
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    for (var position = 1; position <= 6; position++) {
      await tester.tap(find.byKey(ValueKey('lineup-position-$position')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('lineup-player-home-${position - 1}')),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Save lineup'));
    await tester.pumpAndSettle();

    final savedLog =
        (await repository.load()).tournaments.single.games.single.logs.single;
    expect(
      savedLog.lineups.single.playerIds,
      homeTeam.players.map((p) => p.id),
    );
    expect(
      find.text('Set 1 lineup required. Tap R-5 to enable scoring.'),
      findsNothing,
    );
    expect(find.text('V1'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find
                .ancestor(
                  of: find.text('ATT').first,
                  matching: find.byType(OutlinedButton),
                )
                .first,
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('R-5 lineup opens a player dropdown from each court position', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 2);
    final lineupTeam = homeTeam.copyWith(
      players: homeTeam.players.reversed.toList(),
    );
    final initialOrder = homeTeam.players
        .take(6)
        .map((player) => player.id)
        .toList();
    final log = ScorerLog(
      id: 'log',
      gameId: 'game',
      assignedTeamId: homeTeam.id,
      deviceId: 'test-device',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: homeTeam.id,
      lineups: [
        LineupSnapshot(
          teamId: homeTeam.id,
          playerIds: initialOrder,
          recordedAt: now,
        ),
      ],
    );
    final game = Game(
      id: 'game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: now,
      venue: 'Gym',
      status: GameStatus.inProgress,
      logs: [log],
    );
    final tournament = Tournament(
      id: 'tournament',
      name: 'League',
      venue: 'Gym',
      startsOn: now,
      endsOn: now,
      createdAt: now,
      teams: [lineupTeam, awayTeam],
      games: [game],
    );
    final data = AppData(deviceId: 'test-device', tournaments: [tournament]);
    final repository = MemoryAppRepository(data);
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: const MaterialApp(
          home: TrackerPage(tournamentId: 'tournament', gameId: 'game'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('R-5 • Set 1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tap a player on the court'), findsOneWidget);
    expect(find.byKey(const ValueKey('lineup-position-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('lineup-player-home-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('lineup-position-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((item) => item.value),
      homeTeam.players.map((player) => player.id),
    );
    expect(find.byKey(const ValueKey('lineup-player-home-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lineup-player-home-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save lineup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save lineup'));
    await tester.pumpAndSettle();

    final saved = await repository.load();
    final savedLog = saved.tournaments.single.games.single.logs.single;
    final savedOrder = savedLog.lineups.last.playerIds;
    expect(savedOrder.take(2), [
      homeTeam.players[1].id,
      homeTeam.players[0].id,
    ]);
  });

  testWidgets('reconciliation decisions show score choices and raw actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    final now = DateTime.utc(2026, 10, 2);
    final primary = ScorerLog(
      id: 'primary',
      gameId: 'game',
      assignedTeamId: homeTeam.id,
      deviceId: 'device-a',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: homeTeam.id,
      rallies: [
        Rally(
          id: 'rally-a',
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
              id: 'serve-a',
              teamId: homeTeam.id,
              playerId: homeTeam.players.first.id,
              skill: Skill.serve,
              grade: ActionGrade.attempt,
              recordedAt: now,
            ),
            TeamAction(
              id: 'block-a',
              teamId: homeTeam.id,
              playerId: homeTeam.players[1].id,
              skill: Skill.block,
              grade: ActionGrade.success,
              recordedAt: now,
            ),
          ],
        ),
      ],
    );
    final imported = ScorerLog(
      id: 'imported',
      gameId: 'game',
      assignedTeamId: awayTeam.id,
      deviceId: 'device-b',
      createdAt: now,
      updatedAt: now,
      initialServingTeamId: awayTeam.id,
      rallies: [
        Rally(
          id: 'rally-b',
          setNumber: 1,
          sequence: 1,
          winnerTeamId: awayTeam.id,
          homeScore: 0,
          awayScore: 1,
          homeRotation: 1,
          awayRotation: 1,
          servingTeamId: awayTeam.id,
          recordedAt: now,
          actions: [
            TeamAction(
              id: 'attack-b',
              teamId: awayTeam.id,
              playerId: awayTeam.players.first.id,
              skill: Skill.attack,
              grade: ActionGrade.error,
              recordedAt: now,
            ),
          ],
        ),
      ],
    );
    final game = Game(
      id: 'game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: now,
      venue: 'Gym',
      status: GameStatus.awaitingReconciliation,
      logs: [primary, imported],
    );
    final tournament = Tournament(
      id: 'tournament',
      name: 'League',
      venue: 'Gym',
      startsOn: now,
      endsOn: now,
      createdAt: now,
      teams: [homeTeam, awayTeam],
      games: [game],
    );
    final data = AppData(deviceId: 'test-device', tournaments: [tournament]);
    final repository = MemoryAppRepository(data);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: const MaterialApp(
          home: ReconcilePage(tournamentId: 'tournament', gameId: 'game'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Score 1-0'), findsOneWidget);
    expect(find.text('Score 0-1'), findsOneWidget);
    expect(find.text('Device A'), findsNothing);
    expect(find.text('Device B'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(ValueKey('conflict-actions-1:1-${homeTeam.id}')),
          )
          .initialValue,
      'V1\nB2+',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(ValueKey('conflict-actions-1:1-${awayTeam.id}')),
          )
          .initialValue,
      'A7-',
    );
    expect(find.textContaining('winner '), findsNothing);
    expect(find.text('The reconciled match is incomplete'), findsOneWidget);
    expect(
      find.textContaining('Set 1 is 1-0; a team must reach 25'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Best of 5'));
    await tester.tap(find.text('Best of 5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Best of 3').last);
    await tester.pumpAndSettle();
    final savedGame = (await repository.load()).tournaments.single.games.single;
    expect(savedGame.rulesSnapshot?.maxSets, 3);
    expect(savedGame.rulesSnapshot?.setsToWin, 2);

    await tester.ensureVisible(find.text('Manual override'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual override'));
    await tester.pumpAndSettle();
    expect(find.text('Edit individual rallies'), findsOneWidget);
    expect(find.text('Set 1 • Rally 1 • 1-0'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Edit rally'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit rally'));
    await tester.pumpAndSettle();
    expect(find.text('Override set 1, rally 1'), findsOneWidget);
    expect(find.text('Rally actions'), findsOneWidget);
    expect(find.text('Team 1 • HOM'), findsWidgets);
    expect(find.text('Team 2 • AWY'), findsWidgets);
    expect(find.text('serve'), findsNothing);
    await tester.enterText(
      find.byKey(ValueKey('raw-actions-${homeTeam.id}')),
      'R1\nB2+',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'HOM score',
      ),
      '25',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Override reason',
      ),
      'Verified from the scoresheet',
    );
    await tester.tap(find.text('Save override'));
    await tester.pumpAndSettle();
    expect(find.text('Manual override (1)'), findsOneWidget);
    expect(find.text('Set 1 • Rally 1 • 25-0'), findsOneWidget);
    expect(find.text('R1  B2+  A7-'), findsOneWidget);
  });

  testWidgets('finalized games replace reconcile with an audit summary', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 2, 12);
    final primaryRally = Rally(
      id: 'primary-rally',
      setNumber: 1,
      sequence: 1,
      winnerTeamId: homeTeam.id,
      homeScore: 1,
      awayScore: 0,
      homeRotation: 1,
      awayRotation: 1,
      servingTeamId: homeTeam.id,
      recordedAt: now,
    );
    final importedRally = Rally(
      id: 'imported-rally',
      setNumber: 1,
      sequence: 1,
      winnerTeamId: awayTeam.id,
      homeScore: 0,
      awayScore: 1,
      homeRotation: 1,
      awayRotation: 1,
      servingTeamId: awayTeam.id,
      recordedAt: now,
    );
    final primary = testLog(rallies: [primaryRally]);
    final imported = testLog(
      id: 'log-b',
      assignedTeamId: awayTeam.id,
      deviceId: 'device-b',
      rallies: [importedRally],
    );
    final official = testLog(
      id: 'official',
      assignedTeamId: 'official',
      deviceId: 'device-a',
      rallies: [importedRally],
    );
    final game = Game(
      id: 'game',
      tournamentId: 'tournament',
      homeTeamId: homeTeam.id,
      awayTeamId: awayTeam.id,
      scheduledAt: now,
      venue: 'Gym',
      status: GameStatus.finalized,
      logs: [primary, imported],
      officialLog: official,
      revisions: [
        FinalizationRevision(
          id: 'revision',
          finalizedAt: now,
          reason: 'Initial two-device reconciliation',
          officialLog: official,
        ),
      ],
    );
    final tournament = testTournament(games: [game]);
    final data = AppData(deviceId: 'device-a', tournaments: [tournament]);
    final repository = MemoryAppRepository(data);
    final overrides = [
      appRepositoryProvider.overrideWithValue(repository),
      initialAppDataProvider.overrideWithValue(data),
    ];
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: Scaffold(body: GamesPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Reconcile'), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
          home: ReconcilePage(tournamentId: 'tournament', gameId: 'game'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reconciliation summary'), findsOneWidget);
    expect(find.text('HOM 0–1 AWY'), findsOneWidget);
    expect(find.text('Official: 0-1'), findsOneWidget);
    expect(find.text('Option 1: 1-0'), findsOneWidget);
    expect(find.text('Option 2: 0-1'), findsOneWidget);
    expect(find.text('Finalize official match'), findsNothing);
    expect(find.text('Undo reconciliation'), findsOneWidget);

    await tester.tap(find.text('Undo reconciliation'));
    await tester.pumpAndSettle();
    expect(find.text('Undo reconciliation?'), findsOneWidget);
    await tester.tap(find.text('Undo reconciliation').last);
    await tester.pumpAndSettle();
    expect(find.text('Finalize official match'), findsOneWidget);
    final reopened = (await repository.load()).tournaments.single.games.single;
    expect(reopened.status, GameStatus.awaitingReconciliation);
    expect(reopened.officialLog, isNull);
    expect(reopened.revisions, hasLength(1));

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: Scaffold(
            body: TournamentDetailPage(tournamentId: tournament.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Reconciliation summary'), findsNothing);
    expect(find.byTooltip('Reconcile'), findsOneWidget);
  });

  testWidgets('finalized summary filters player stats by team and set', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 2, 12);
    TeamAction action(
      String id,
      String teamId,
      String? playerId,
      Skill skill,
      ActionGrade grade,
    ) => TeamAction(
      id: id,
      teamId: teamId,
      playerId: playerId,
      skill: skill,
      grade: grade,
      recordedAt: now,
    );
    final official =
        testLog(
          id: 'official',
          rallies: [
            Rally(
              id: 'set-one',
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
                action(
                  'serve',
                  homeTeam.id,
                  homeTeam.players.first.id,
                  Skill.serve,
                  ActionGrade.success,
                ),
                action(
                  'receive',
                  awayTeam.id,
                  awayTeam.players.first.id,
                  Skill.reception,
                  ActionGrade.attempt,
                ),
                action(
                  'op',
                  homeTeam.id,
                  null,
                  Skill.opponentError,
                  ActionGrade.success,
                ),
              ],
            ),
            Rally(
              id: 'set-two',
              setNumber: 2,
              sequence: 1,
              winnerTeamId: awayTeam.id,
              homeScore: 0,
              awayScore: 1,
              homeRotation: 1,
              awayRotation: 1,
              servingTeamId: awayTeam.id,
              recordedAt: now,
              actions: [
                action(
                  'attack',
                  homeTeam.id,
                  homeTeam.players.first.id,
                  Skill.attack,
                  ActionGrade.error,
                ),
                action(
                  'block',
                  awayTeam.id,
                  awayTeam.players.first.id,
                  Skill.block,
                  ActionGrade.success,
                ),
                action(
                  'fault',
                  homeTeam.id,
                  null,
                  Skill.teamFault,
                  ActionGrade.error,
                ),
              ],
            ),
            Rally(
              id: 'set-three',
              setNumber: 3,
              sequence: 1,
              winnerTeamId: homeTeam.id,
              homeScore: 1,
              awayScore: 0,
              homeRotation: 1,
              awayRotation: 1,
              servingTeamId: homeTeam.id,
              recordedAt: now,
            ),
          ],
        ).copyWith(
          lineups: [
            for (final setNumber in [1, 2, 3]) ...[
              LineupSnapshot(
                teamId: homeTeam.id,
                playerIds: homeTeam.players.map((player) => player.id).toList(),
                setNumber: setNumber,
              ),
              LineupSnapshot(
                teamId: awayTeam.id,
                playerIds: awayTeam.players.map((player) => player.id).toList(),
                setNumber: setNumber,
              ),
            ],
          ],
        );
    final game = testGame(officialLog: official).copyWith(
      rulesSnapshot: const MatchRules(
        setsToWin: 2,
        maxSets: 3,
        regularSetTarget: 1,
        decidingSetTarget: 1,
        winBy: 1,
      ),
    );
    final data = AppData(
      deviceId: 'test-device',
      tournaments: [
        testTournament(games: [game]),
      ],
    );
    final repository = MemoryAppRepository(data);
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: const MaterialApp(
          home: ReconcilePage(tournamentId: 'tournament', gameId: 'game'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    String cell(DataTable table, int row, int column) =>
        (table.rows[row].cells[column].child as Text).data!;
    expect(find.text('Player stats'), findsOneWidget);
    expect(find.text('Team totals: OP+ 1  •  T− 1'), findsOneWidget);
    expect(find.text('Serve 0 / 1 / 0'), findsOneWidget);
    var table = tester.widget<DataTable>(find.byType(DataTable));
    expect(cell(table, 0, 1), 'Home 1');
    expect(cell(table, 0, 2), '3');
    expect(cell(table, 0, 4), '0 / 1 / 0');
    expect(cell(table, 0, 7), '0 / 0 / 1');

    await tester.tap(find.widgetWithText(ChoiceChip, 'AWY'));
    await tester.pumpAndSettle();
    table = tester.widget<DataTable>(find.byType(DataTable));
    expect(cell(table, 0, 1), 'Away 1');
    expect(cell(table, 0, 6), '1 / 0 / 0');
    expect(cell(table, 0, 8), '0 / 1 / 0');
    expect(find.text('Reception 1 / 0 / 0'), findsOneWidget);

    await tester.tap(find.text('All sets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set 2').last);
    await tester.pumpAndSettle();
    table = tester.widget<DataTable>(find.byType(DataTable));
    expect(cell(table, 0, 2), '1');
    expect(cell(table, 0, 6), '0 / 0 / 0');
    expect(cell(table, 0, 8), '0 / 1 / 0');
    expect(find.text('Reception 0 / 0 / 0'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports render the ordered player stats summary matrix', (
    tester,
  ) async {
    final data = AppData(
      deviceId: 'test-device',
      tournaments: [testTournament()],
    );
    final repository = MemoryAppRepository(data);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: const MaterialApp(home: Scaffold(body: ReportsPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Player stats summary'), findsOneWidget);
    expect(find.text('Team'), findsWidgets);
    expect(find.text('Last name'), findsOneWidget);
    expect(find.text('S+'), findsOneWidget);
    expect(find.text('V-'), findsOneWidget);
    expect(find.text('OP+'), findsOneWidget);
    expect(find.text('T-'), findsOneWidget);
    expect(find.text('Games played'), findsOneWidget);
    expect(find.text('Sets played'), findsOneWidget);
    expect(find.text('Games won'), findsOneWidget);
  });

  testWidgets('games tab offers game package export', (tester) async {
    final game = testGame(logs: [testLog(deviceId: 'test-device')]);
    final data = AppData(
      deviceId: 'test-device',
      tournaments: [
        testTournament(games: [game]),
      ],
    );
    final repository = MemoryAppRepository(data);
    await tester.binding.setSurfaceSize(const Size(900, 700));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: const MaterialApp(home: Scaffold(body: GamesPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Game actions'));
    await tester.pumpAndSettle();

    expect(find.text('Export scorer log'), findsOneWidget);
    expect(find.text('Delete game'), findsOneWidget);
  });

  testWidgets('new game dialog opens a scheduled time picker', (tester) async {
    final tournament = testTournament();
    final data = AppData(deviceId: 'test-device', tournaments: [tournament]);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(MemoryAppRepository(data)),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TournamentDetailPage(tournamentId: tournament.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add game').first);
    await tester.pumpAndSettle();
    expect(find.text('Scheduled date'), findsOneWidget);
    expect(find.text('Scheduled time'), findsOneWidget);
    expect(
      find.text(
        DateFormat.jm().format(
          tournament.startsOn.add(const Duration(hours: 9)),
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Scheduled time'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
  });

  testWidgets('tournament deletion requires destructive confirmation', (
    tester,
  ) async {
    final tournament = testTournament(games: [testGame()]);
    final data = AppData(deviceId: 'test-device', tournaments: [tournament]);
    final repository = MemoryAppRepository(data);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRepositoryProvider.overrideWithValue(repository),
          initialAppDataProvider.overrideWithValue(data),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TournamentDetailPage(tournamentId: tournament.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit tournament'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Best of 5'));
    await tester.pumpAndSettle();
    expect(find.text('One set'), findsOneWidget);
    await tester.tap(find.text('One set'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete tournament'));
    await tester.pumpAndSettle();

    expect(find.text('Delete tournament?'), findsOneWidget);
    expect(find.textContaining('2 teams and 1 game'), findsOneWidget);
    expect(find.textContaining('This cannot be undone.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete tournament?'), findsNothing);
    expect((await repository.load()).tournaments, hasLength(1));
  });
}
