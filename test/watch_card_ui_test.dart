import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/presentation/agent_details_screen.dart';

void main() {
  testWidgets('L1 shows exact link and successful read method', (
    t,
  ) async {
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      if (await f.exists()) {
        final l = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
        await l.load();
      }
    });
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(
      Agent(
        title: 'Drishyam ticket watch',
        originalPrompt: 'Notify below 200',
        type: AgentType.valueWatch,
        status: AgentStatus.active,
        createdAt: DateTime(2026, 10, 7),
        checkInterval: const Duration(minutes: 30),
        condition: WatchCondition.lessThan,
        target: 200,
        sourceUrl: 'https://in.bookmyshow.com/movies/ichalkaranji/seat-layout/ET00477911/frts/33331/20261008',
      lastSuccessfulReadAt:DateTime(2026,10,7,23,40),
      lastSuccessfulValue:150,
      lastReadMethod:'Browser read (user started)',
      lastReadSourceUrl:'https://in.bookmyshow.com/movies/ichalkaranji/seat-layout/ET00477911/frts/33331/20261008',
      ),
    );
    await t.binding.setSurfaceSize(const Size(412, 1100));
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: AgentDetailsScreen(
            repo: repo,
            checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
            agentId: id,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Browser read (user started)'), findsOneWidget);
    expect(find.textContaining('Last successful read: 7/10 23:40'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final im =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/lookout-l1.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
  });
}
