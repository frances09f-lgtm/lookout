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

Future<void> _seed(AgentRepository repo, int id) async {
  final t1 = DateTime(2026, 10, 22, 9, 12);
  await repo.logActivity(id, 'Started check', t1);
  final t2 = DateTime(2026, 10, 21, 18, 40);
  await repo.logActivity(id, 'Started check', t2);
  await repo.logActivity(
      id, 'Unable to check: Fetching shop.example timed out - no fresh value to check', t2);
  await repo.logActivity(id, 'Read retry scheduled for 21/10 19:10', t2);
  final t3 = DateTime(2026, 10, 21, 15, 2);
  await repo.logActivity(id, 'Started check', t3);
  await repo.logActivity(
      id, 'Fetched data: Product offer 2199.0 on shop.example - target 2000', t3);
  await repo.logActivity(id, 'Condition not met', t3);
  await repo.logActivity(id, 'Next check due from 21/10 15:32', t3);
  final t4 = DateTime(2026, 10, 21, 15, 32);
  await repo.logActivity(id, 'Started check', t4);
  await repo.logActivity(
      id, 'Fetched data: Product offer 1990.0 on shop.example - target 2000', t4);
  await repo.logActivity(id, 'Condition met', t4);
  await repo.logActivity(id, 'Notification sent', t4);
  await repo.logActivity(id, 'Agent completed', t4);
}

void main() {
  for (final dark in [true, false]) {
    testWidgets('history groups one pill per check cycle (dark=$dark)',
        (t) async {
      await t.runAsync(() async {
        await Directory('/tmp/lookout-shots').create(recursive: true);
        await loadTestFonts();
        // Real icon glyphs in the render (bundled with Flutter on device).
        const sdk = String.fromEnvironment('FLUTTER_SDK');
        final mi = File(
            '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
        if (await mi.exists()) {
          final l = FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(await mi.readAsBytes())));
          await l.load();
        }
      });
      final repo = InMemoryAgentRepository();
      addTearDown(repo.close);
      final id = await repo.insertAgent(_task(1));
      await _seed(repo, id);

      await t.binding.setSurfaceSize(const Size(390, 844));
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
          home: RepaintBoundary(
            key: key,
            child: ActivityScreen(repo: repo, agentId: id),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 500));

      // Four cycles from ten log lines, each with its honest state.
      // 'Started check' = the no-result card title + a step in the 3
      // completed cycles.
      expect(find.text('Started check'), findsNWidgets(4));
      expect(find.text('NO RESULT'), findsOneWidget);
      expect(find.text('No result recorded for this cycle'), findsOneWidget);
      expect(find.text('Unable to check'), findsOneWidget);
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('Condition not met'), findsOneWidget);
      expect(find.text('NOT YET'), findsOneWidget);
      expect(find.text('Condition met'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
      // The state line is not duplicated inside its own card.
      expect(find.text('Next check due from 21/10 15:32'), findsOneWidget);
      expect(find.text('Read retry scheduled for 21/10 19:10'), findsOneWidget);
      expect(find.text('Notification sent'), findsOneWidget);
      expect(find.text('Agent completed'), findsOneWidget);
      expect(t.takeException(), isNull);

      await t.runAsync(() async {
        final im = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final d = await im.toByteData(format: ui.ImageByteFormat.png);
        await File(
                '/tmp/lookout-shots/history-pills-${dark ? 'dark' : 'light'}.png')
            .writeAsBytes(d!.buffer.asUint8List());
      });
    });
  }
}
