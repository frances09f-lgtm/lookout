import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/activity.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/activity_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_fonts.dart';

Agent _task(int id) => Agent(
      id: id,
      title: 'wireless earbuds below 2000',
      originalPrompt: 'below 2000',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 10, 21),
      checkInterval: const Duration(minutes: 30),
      condition: WatchCondition.lessThan,
      target: 2000,
    );

Future<void> _seedCycles(AgentRepository repo, int id) async {
  final t1 = DateTime(2026, 10, 25, 3, 15);
  await repo.logActivity(id, 'Started check', t1);
  await repo.logActivity(
      id, 'Fetched data: Product offer 1990.0 on shop.example - target 2000', t1);
  await repo.logActivity(id, 'Condition met', t1);
  await repo.logActivity(id, 'Notification sent', t1);
  final t2 = DateTime(2026, 10, 24, 22, 40);
  await repo.logActivity(id, 'Started check', t2);
  await repo.logActivity(
      id, 'Unable to check: Fetching shop.example timed out - no fresh value to check', t2);
  final t3 = DateTime(2026, 10, 24, 21, 2);
  await repo.logActivity(id, 'Started check', t3);
  await repo.logActivity(
      id, 'Fetched data: Product offer 2199.0 on shop.example - target 2000', t3);
  await repo.logActivity(id, 'Condition not met', t3);
  await repo.logActivity(id, 'Next check scheduled for 24/10 21:32', t3);
}

class BrokenKvRepo extends InMemoryAgentRepository {
  @override
  Future<String?> getKv(String key) => throw StateError('kv store unreadable');
}

class BrokenActivityRepo extends InMemoryAgentRepository {
  @override
  Future<List<ActivityEntry>> activityFor(int agentId, {int limit = 100}) =>
      Future.error(StateError('activity table gone'));
}

Future<void> _shoot(WidgetTester t, Widget screen, String name,
    {bool dark = false}) async {
  await t.runAsync(() async {
    await Directory('/tmp/lookout-shots').create(recursive: true);
    await loadTestFonts();
    const sdk = String.fromEnvironment('FLUTTER_SDK');
    final mi = File(
        '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (await mi.exists()) {
      final l = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(await mi.readAsBytes())));
      await l.load();
    }
  });
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(const Size(390, 844));
  final key = GlobalKey();
  await t.pumpWidget(
    MaterialApp(
      theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
      home: RepaintBoundary(key: key, child: screen),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
  await t.pump(const Duration(milliseconds: 500));
  expect(t.takeException(), isNull);
  await t.runAsync(() async {
    final im = await (key.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 2);
    final d = await im.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/lookout-shots/$name.png')
        .writeAsBytes(d!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('v1.1.9 worker status: completed run + partial note + history',
      (t) async {
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final id = await repo.insertAgent(_task(1));
    await _seedCycles(repo, id);
    await repo.putKv('lastBackgroundRunStartedAt',
        DateTime(2026, 10, 25, 3, 15).toIso8601String());
    await repo.putKv('lastBackgroundRunAt',
        DateTime(2026, 10, 25, 3, 17).toIso8601String());
    await repo.putKv('lastBackgroundNote',
        'Checked 4 of 9 due tasks within the background time budget; the rest stay due for the next cycle.');
    await _shoot(t, ActivityScreen(repo: repo, agentId: id),
        'v119-status-healthy-light');
    expect(find.textContaining('Background worker last completed: 25/10 03:17'),
        findsOneWidget);
    expect(find.textContaining('Checked 4 of 9 due tasks'), findsOneWidget);
  });

  testWidgets('v1.1.9 worker status: started but never completed', (t) async {
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final id = await repo.insertAgent(_task(2));
    await repo.putKv('lastBackgroundRunStartedAt',
        DateTime(2026, 10, 25, 3, 15).toIso8601String());
    await _shoot(t, ActivityScreen(repo: repo, agentId: id),
        'v119-status-anomaly-light');
    expect(find.textContaining('no completed run was recorded'), findsOneWidget);
  });

  testWidgets('v1.1.9 worker status: store read failure is shown redacted',
      (t) async {
    final repo = BrokenKvRepo();
    addTearDown(repo.close);
    final id = await repo.insertAgent(_task(3));
    await _shoot(t, ActivityScreen(repo: repo, agentId: id),
        'v119-status-readerror-dark',
        dark: true);
    expect(find.textContaining('Background worker status could not be read'),
        findsOneWidget);
  });

  testWidgets('v1.1.9 Task14 view: history load failure shows the reason',
      (t) async {
    final repo = BrokenActivityRepo();
    addTearDown(repo.close);
    final id = await repo.insertAgent(_task(4));
    await _shoot(t, ActivityScreen(repo: repo, agentId: id),
        'v119-history-error-light');
    expect(find.text('Could not load this task’s history.'), findsOneWidget);
    expect(find.textContaining('activity table gone'), findsOneWidget);
  });
}
