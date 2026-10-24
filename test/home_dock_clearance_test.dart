import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'test_fonts.dart';

void main() {
  testWidgets('last card actions scroll clear of the dock', (t) async {
    await t.runAsync(loadTestFonts);
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    for (var i = 0; i < 3; i++) {
      await repo.insertAgent(Agent(
        title: 'Watch number $i below 100',
        originalPrompt: 'p', type: AgentType.valueWatch,
        status: i == 2 ? AgentStatus.completed : AgentStatus.active,
        createdAt: DateTime(2026, 10, 20),
        checkInterval: const Duration(hours: 1),
        condition: WatchCondition.lessThan,
        target: 100, currentValue: 99.0 + i,
        lastCheckedAt: DateTime(2026, 10, 24, 23),
      ));
    }
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final key = GlobalKey();
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await t.pumpWidget(MaterialApp(
      theme: LookoutTheme.dark(),
      home: RepaintBoundary(
          key: key, child: HomeScreen(repo: repo, checker: checker)),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    // Scroll to the very bottom; the completed card's History must be
    // tappable above the floating dock.
    await t.drag(find.byType(ListView), const Offset(0, -1000));
    await t.pumpAndSettle();
    final history = find.text('History').last;
    final topLeft = t.getTopLeft(history);
    expect(topLeft.dy, lessThan(844 - 96)); // clear of the dock band
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/lookout-shots/home-dock-clearance.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
    expect(t.takeException(), isNull);
  });
}
