import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/expressive.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'test_fonts.dart';

Agent _agent({required int id, required AgentStatus status}) => Agent(
      id: id, // id 2 seeds the sky pastel pair, matching the user's card
      title: 'Tell me when Bitcoin Price rises above 80800',
      originalPrompt: 'p',
      type: AgentType.valueWatch,
      status: status,
      createdAt: DateTime(2026, 10, 22),
      checkInterval: const Duration(minutes: 30),
      condition: WatchCondition.greaterThan,
      target: 80800,
      currentValue: 80362.80,
      lastCheckedAt: DateTime(2026, 10, 25, 18, 21),
    );

Future<void> _card(WidgetTester t, Agent agent, bool dark, String name,
    {void Function(Switch sw)? inspect}) async {
  await t.binding.setSurfaceSize(const Size(390, 340));
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
  await t.pump(const Duration(milliseconds: 400));
  final sw = t.widget<Switch>(find.byType(Switch));
  inspect?.call(sw);
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
  setUpAll(() async {
    await Directory('/tmp/lookout-shots').create(recursive: true);
  });

  testWidgets('switch ON/OFF reads clearly in both themes', (t) async {
    await t.runAsync(() async {
      await loadTestFonts();
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

    // ON, dark: deep sky track (not the washed pastel), white thumb.
    await _card(t, _agent(id: 2, status: AgentStatus.active), true,
        'v1111-switch-on-dark', inspect: (sw) {
      expect(sw.value, isTrue);
      expect(sw.activeTrackColor, XColors.skyDeep);
      expect(sw.activeThumbColor, Colors.white);
    });
    // ON, light: same deep track as before - unchanged by the fix.
    await _card(t, _agent(id: 2, status: AgentStatus.active), false,
        'v1111-switch-on-light', inspect: (sw) {
      expect(sw.value, isTrue);
      expect(sw.activeTrackColor, XColors.skyDeep);
      expect(sw.activeThumbColor, Colors.white);
    });
    // OFF, dark: muted thumb on dark track, no accent.
    await _card(t, _agent(id: 2, status: AgentStatus.paused), true,
        'v1111-switch-off-dark', inspect: (sw) {
      expect(sw.value, isFalse);
      expect(sw.inactiveTrackColor, isNot(XColors.sky));
    });
    // OFF, light.
    await _card(t, _agent(id: 2, status: AgentStatus.paused), false,
        'v1111-switch-off-light', inspect: (sw) {
      expect(sw.value, isFalse);
    });
  });
}
