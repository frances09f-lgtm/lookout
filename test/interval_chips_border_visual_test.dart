import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'test_fonts.dart';

Future<void> _snap(GlobalKey key, String name) async {
  final im = await (key.currentContext!.findRenderObject()
          as RenderRepaintBoundary)
      .toImage(pixelRatio: 1.5);
  final d = await im.toByteData(format: ui.ImageByteFormat.png);
  await File('/tmp/lookout-shots/$name.png').writeAsBytes(d!.buffer.asUint8List());
}

void main() {
  for (final dark in [true, false]) {
    testWidgets('bordered interval chips create (dark=$dark)', (t) async {
      await t.runAsync(() async {
        await Directory('/tmp/lookout-shots').create(recursive: true);
        await loadTestFonts();
      });
      final repo = InMemoryAgentRepository();
      addTearDown(repo.close);
      await t.binding.setSurfaceSize(const Size(390, 2400));
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
          home: RepaintBoundary(
            key: key,
            child: CreateAgentScreen(repo: repo),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(0), 'Gold');
      await t.enterText(find.byType(TextField).at(1), '4,030');
      await t.enterText(
        find.byType(TextField).at(2),
        'https://example.com/gold',
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.widgetWithText(FilledButton, 'Review watch'));
      await t.pumpAndSettle();
      expect(find.text('Check every'), findsOneWidget);
      await t.runAsync(() => _snap(key, 'v1124-chips-border-${dark ? 'dark' : 'light'}'));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('bordered interval chips details screen', (t) async {
    await t.runAsync(() async {
      await Directory('/tmp/lookout-shots').create(recursive: true);
      await loadTestFonts();
    });
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    final id = await repo.insertAgent(
      Agent(
        id: null,
        title: 'Gold',
        originalPrompt: 'p',
        type: AgentType.valueWatch,
        status: AgentStatus.active,
        createdAt: DateTime(2026, 10, 1),
        lastCheckedAt: null,
        completedAt: null,
        nextCheckAt: null,
        checkInterval: const Duration(minutes: 15),
        condition: WatchCondition.lessThan,
        target: 4030,
        currentValue: 4010,
        previousValue: null,
        sourceUrl: 'https://example.com/gold',
        sourceIdentity: null,
        notificationEnabled: true,
        lastSuccessfulReadAt: null,
        lastSuccessfulValue: null,
        lastReadMethod: null,
        lastReadSourceUrl: null,
        consecutiveSourceBlocks: 0,
      ),
    );
    for (final dark in [true, false]) {
      await t.binding.setSurfaceSize(const Size(390, 2400));
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
          home: RepaintBoundary(
            key: key,
            child: AgentDetailsScreen(repo: repo, checker: checker, agentId: id),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.runAsync(() => _snap(key, 'v1124-details-border-${dark ? 'dark' : 'light'}'));
      expect(t.takeException(), isNull);
    }
  });
}
