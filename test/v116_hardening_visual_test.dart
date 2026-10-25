import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/activity_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'test_fonts.dart';

Agent _task(int id, {DateTime? nextCheckAt}) => Agent(
  id: id,
  title: 'bitcoin above 80260',
  originalPrompt: 'above 80260',
  type: AgentType.valueWatch,
  status: AgentStatus.active,
  createdAt: DateTime(2026, 10, 21),
  checkInterval: const Duration(hours: 1),
  condition: WatchCondition.greaterThan,
  target: 80260,
  nextCheckAt: nextCheckAt,
);

Future<void> _loadFonts() async {
  await loadTestFonts();
  const sdk = String.fromEnvironment('FLUTTER_SDK');
  final mi = File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (await mi.exists()) {
    final l = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(await mi.readAsBytes())));
    await l.load();
  }
}

Future<void> _shot(GlobalKey key, String name) async {
  final im = await (key.currentContext!.findRenderObject()
          as RenderRepaintBoundary)
      .toImage(pixelRatio: 2);
  final d = await im.toByteData(format: ui.ImageByteFormat.png);
  await File('/tmp/lookout-shots/$name.png')
      .writeAsBytes(d!.buffer.asUint8List());
}

void main() {
  testWidgets('edit-only group renders as Task updated, with schedule lines',
      (t) async {
    await t.runAsync(() async {
      await Directory('/tmp/lookout-shots').create(recursive: true);
      await _loadFonts();
    });
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final next = DateTime.now().add(const Duration(hours: 1));
    final id = await repo.insertAgent(_task(1, nextCheckAt: next));
    final editAt = DateTime.now().subtract(const Duration(hours: 9));
    await repo.logActivity(id, 'Target changed to 80260.0', editAt);
    await repo.putKv(
        'lastBackgroundRunAt',
        DateTime.now().subtract(const Duration(minutes: 7)).toIso8601String());

    await t.binding.setSurfaceSize(const Size(390, 844));
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: LookoutTheme.light(),
        home: RepaintBoundary(
          key: key,
          child: ActivityScreen(repo: repo, agentId: id),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));

    expect(find.text('Task updated'), findsOneWidget);
    expect(find.text('SAVED'), findsOneWidget);
    expect(find.text('Started check'), findsNothing);
    expect(find.text('NO RESULT'), findsNothing);
    expect(find.textContaining('Checks every 1 h'), findsOneWidget);
    expect(find.textContaining('next check scheduled for'), findsOneWidget);
    expect(find.textContaining('Background worker last ran:'), findsOneWidget);
    expect(find.textContaining('(app-wide)'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.runAsync(() => _shot(key, 'v116-edit-group'));
  });

  testWidgets('interrupted check shows banner, no background run line',
      (t) async {
    await t.runAsync(() async {
      await Directory('/tmp/lookout-shots').create(recursive: true);
      await _loadFonts();
    });
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final id = await repo.insertAgent(_task(1));
    final at = DateTime.now().subtract(const Duration(minutes: 40));
    await repo.logActivity(id, 'Started check', at);

    await t.binding.setSurfaceSize(const Size(390, 844));
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: LookoutTheme.light(),
        home: RepaintBoundary(
          key: key,
          child: ActivityScreen(repo: repo, agentId: id),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(milliseconds: 500));

    expect(find.text('Started check'), findsOneWidget);
    expect(find.text('A check started, but no result was recorded. The reason is unknown.'), findsOneWidget);
    expect(find.text('Background worker has no recorded run yet (app-wide).'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.runAsync(() => _shot(key, 'v116-interrupted-banner'));
  });
}
