import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/activity_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'test_fonts.dart';

Agent _task(int id, Duration interval, DateTime nextCheckAt) => Agent(
  id: id,
  title: 'gold above 4030',
  originalPrompt: 'Tell me when Gold Price rises above 4030',
  type: AgentType.valueWatch,
  status: AgentStatus.active,
  createdAt: DateTime(2026, 10, 29),
  checkInterval: interval,
  condition: WatchCondition.greaterThan,
  target: 4030,
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

Future<void> _render(WidgetTester t, Agent agent, InMemoryAgentRepository repo,
    GlobalKey key) async {
  await t.binding.setSurfaceSize(const Size(390, 844));
  await t.pumpWidget(
    MaterialApp(
      theme: LookoutTheme.light(),
      home: RepaintBoundary(
        key: key,
        child: ActivityScreen(repo: repo, agentId: agent.id!),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('5-minute task shows due-from wording plus background caveat',
      (t) async {
    await t.runAsync(() async {
      await Directory('/tmp/lookout-shots').create(recursive: true);
      await _loadFonts();
    });
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final next = DateTime.now().add(const Duration(minutes: 5));
    final id = await repo.insertAgent(
        _task(1, const Duration(minutes: 5), next));

    final key = GlobalKey();
    await _render(t, _task(id, const Duration(minutes: 5), next), repo, key);

    expect(find.textContaining('Checks every 5 min'), findsOneWidget);
    expect(find.textContaining('next check due from'), findsOneWidget);
    expect(
        find.text('Background checks may run later than the due time.'),
        findsOneWidget);
    expect(find.textContaining('scheduled for'), findsNothing);
    expect(t.takeException(), isNull);

    await t.runAsync(() => _shot(key, 'v1121-due-from-5min'));
  });

  testWidgets('hourly task shows due-from wording without the caveat',
      (t) async {
    await t.runAsync(() async {
      await Directory('/tmp/lookout-shots').create(recursive: true);
      await _loadFonts();
    });
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final next = DateTime.now().add(const Duration(hours: 1));
    final id =
        await repo.insertAgent(_task(1, const Duration(hours: 1), next));

    final key = GlobalKey();
    await _render(t, _task(id, const Duration(hours: 1), next), repo, key);

    expect(find.textContaining('Checks every 1 h'), findsOneWidget);
    expect(find.textContaining('next check due from'), findsOneWidget);
    expect(
        find.text('Background checks may run later than the due time.'),
        findsNothing);
    expect(t.takeException(), isNull);

    await t.runAsync(() => _shot(key, 'v1121-due-from-1h'));
  });
}
