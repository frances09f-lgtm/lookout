import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'test_fonts.dart';

void main() {
  final agent = Agent(
    id: 1,
    title: 'iPhone 15 128GB below 60000',
    originalPrompt: 'p',
    type: AgentType.valueWatch,
    status: AgentStatus.active,
    createdAt: DateTime(2026, 10, 22),
    checkInterval: const Duration(minutes: 30),
    condition: WatchCondition.lessThan,
    target: 60000,
    currentValue: 67999,
    lastCheckedAt: DateTime(2026, 10, 22, 18, 26),
  );

  for (final dark in [false, true]) {
    testWidgets('watch card buttons readable (dark=$dark)', (t) async {
      await t.runAsync(() async {
        await Directory('/tmp/lookout-shots').create(recursive: true);
        await loadTestFonts();
      });
      await t.binding.setSurfaceSize(const Size(390, 500));
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AgentCard(
                  agent: agent,
                  onTap: () {},
                  onRunNow: () {},
                  onHistory: () {},
                  onPauseResume: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Run now'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final im = await (key.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
        final d = await im.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/lookout-shots/card-${dark ? 'dark' : 'light'}.png')
            .writeAsBytes(d!.buffer.asUint8List());
      });

    });
  }
}
