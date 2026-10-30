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
import 'package:shared_preferences/shared_preferences.dart';
import 'test_fonts.dart';

Future<void> _snap(GlobalKey key, String name) async {
  final im = await (key.currentContext!.findRenderObject()
          as RenderRepaintBoundary)
      .toImage(pixelRatio: 1.5);
  final d = await im.toByteData(format: ui.ImageByteFormat.png);
  await File('/tmp/lookout-shots/$name.png').writeAsBytes(d!.buffer.asUint8List());
}

Agent task({int? id}) => Agent(
      id: id,
      title: 'Gold watch',
      originalPrompt: 'below 4030',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 10, 15, 12),
      checkInterval: const Duration(minutes: 5),
      condition: WatchCondition.lessThan,
      target: 4030,
      currentValue: 4040,
      nextCheckAt: DateTime(2026, 10, 15, 12, 5),
    );

void main() {
  const channel = MethodChannel('lookout/alarms');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final dark in [true, false]) {
    for (final state in [
      (exact: false, battery: false, label: 'both-off'),
      (exact: true, battery: false, label: 'battery-off'),
      (exact: true, battery: true, label: 'both-on'),
    ]) {
      testWidgets('alarm engine line ${state.label} (dark=$dark)', (t) async {
        await t.runAsync(() async {
          await Directory('/tmp/lookout-shots').create(recursive: true);
          await loadTestFonts();
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'canScheduleExactAlarms':
              return state.exact;
            case 'isIgnoringBatteryOptimizations':
              return state.battery;
            default:
              return null;
          }
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final repo = InMemoryAgentRepository();
        addTearDown(repo.close);
        final id = await repo.insertAgent(task());
        await t.binding.setSurfaceSize(const Size(390, 900));
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
        await t.pumpAndSettle();
        if (state.exact && state.battery) {
          expect(find.text('On-time checks (exact alarms): on.'), findsOneWidget);
        } else {
          expect(
            find.textContaining('On-time checks (exact alarms): off'),
            findsOneWidget,
          );
        }
        await t.runAsync(() => _snap(key,
            'v1124-alarm-engine-${state.label}-${dark ? 'dark' : 'light'}'));
        expect(t.takeException(), isNull);
      });
    }
  }
}
