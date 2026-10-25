import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/main.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_fonts.dart';

Future<void> _fonts() async {
  await Directory('/tmp/lookout-shots').create(recursive: true);
  await loadTestFonts();
  const sdk = String.fromEnvironment('FLUTTER_SDK');
  final mi =
      File('$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (await mi.exists()) {
    final l = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(await mi.readAsBytes())));
    await l.load();
  }
}

Future<void> _snap(WidgetTester t, GlobalKey key, String name) async {
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('v1.1.10 boot error screen (light + dark)', (t) async {
    await t.runAsync(_fonts);
    await t.binding.setSurfaceSize(const Size(390, 844));
    for (final dark in [false, true]) {
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
          home: RepaintBoundary(
            key: key,
            child: LookoutRoot(
              openStore: () async =>
                  throw StateError('database is corrupted'),
              initNotifications: (onTap) async => RecordingNotifier(),
              initBackground: () async {},
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Lookout could not start'), findsOneWidget);
      await _snap(t, key, 'v1110-boot-error-${dark ? 'dark' : 'light'}');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('v1.1.10 scheduling-failure banner over the open app',
      (t) async {
    await t.runAsync(_fonts);
    await t.binding.setSurfaceSize(const Size(390, 844));
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: LookoutRoot(
          openStore: () async => InMemoryAgentRepository(),
          initNotifications: (onTap) async => RecordingNotifier(),
          initBackground: () async =>
              throw StateError('workmanager init failed'),
        ),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Automatic checks could not be scheduled'),
        findsOneWidget);
    await _snap(t, key, 'v1110-scheduler-warning-banner');
    expect(t.takeException(), isNull);
  });
}
