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
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/presentation/theme.dart';

void main() {
  testWidgets('dark home shows accurate counts and icon controls', (t) async {
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      final icons = File(
        '${Platform.environment['FLUTTER_ROOT'] ?? '/home/sandbox/flutter'}/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        final l = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          );
        await l.load();
      }
      if (await f.exists()) {
        final l = FontLoader('Roboto')
          ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
        await l.load();
      }
    });
    final repo = InMemoryAgentRepository();
    final now = DateTime.now();
    for (final item in [
      ("iPhone 15 price", AgentStatus.active, 54000.0),
      ("Drishyam tickets", AgentStatus.paused, 150.0),
      ("Laptop offer", AgentStatus.completed, 50000.0),
      ("Product price unavailable", AgentStatus.failed, 20000.0),
    ]) {
      await repo.insertAgent(
        Agent(
          title: item.$1,
          originalPrompt: 'test fixture',
          type: AgentType.valueWatch,
          status: item.$2,
          createdAt: now,
          checkInterval: const Duration(minutes: 30),
          condition: WatchCondition.lessThan,
          target: item.$3,
          lastCheckedAt: now.subtract(const Duration(minutes: 2)),
        ),
      );
    }
    await t.binding.setSurfaceSize(const Size(412, 915));
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: LookoutTheme.dark(),
        home: RepaintBoundary(
          key: key,
          child: HomeScreen(
            repo: repo,
            checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Checked 2m ago'), findsNWidgets(3));
    expect(find.text('Checked just now'), findsOneWidget);
    expect(find.byTooltip('Run now'), findsNWidgets(4));
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final im =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/lookout-dark-home.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
    await t.tap(find.byTooltip('Pause').first);
    await t.pumpAndSettle();
    expect(
      (await repo.allAgents())
          .where((a) => a.status == AgentStatus.paused)
          .length,
      2,
    );
  });
}
