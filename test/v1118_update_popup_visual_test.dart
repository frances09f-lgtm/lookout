import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/update/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_fonts.dart';

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

/// Replays the exact body served by the live feed at test time.
class _FeedClient extends http.BaseClient {
  _FeedClient(this.body);
  final String body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  testWidgets('v1.1.20 update dialog renders the live feed', (t) async {
    String liveBody = '';
    await t.runAsync(() async {
      await Directory('/tmp/lookout-shots').create(recursive: true);
      await _loadFonts();
      HttpOverrides.global = null;
      final r = await http
          .get(Uri.parse('https://lookout-apk.pages.dev/update.json'));
      expect(r.statusCode, 200);
      liveBody = r.body;
      final v = jsonDecode(liveBody)['lookout']['version'];
      expect(v, '1.1.20');
    });
    SharedPreferences.setMockInitialValues({});
    debugRunUpdateChecksInTests = true;
    addTearDown(() => debugRunUpdateChecksInTests = false);
    await t.binding.setSurfaceSize(const Size(390, 844));
    final rootKey = GlobalKey();
    // Users upgrade from 1.1.16 (last feed version) - dialog must show 1.1.18.
    UpdateChecker checker() => UpdateChecker(
          client: _FeedClient(liveBody),
          currentVersion: () async => '1.1.16',
          canInstall: () async => true,
        );

    Widget host(ThemeData theme) => RepaintBoundary(
          key: rootKey,
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(title: const Text('Lookout')),
              body: Center(
                child: Builder(
                  builder: (ctx) => FilledButton(
                    onPressed: () =>
                        checkUpdateManually(ctx, checker: checker()),
                    child: const Text('Check for updates'),
                  ),
                ),
              ),
            ),
          ),
        );

    await t.pumpWidget(host(LookoutTheme.light()));
    await t.tap(find.text('Check for updates'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Lookout 1.1.20 is available'), findsOneWidget);
    await t.runAsync(() => _shot(rootKey, 'v1118-dialog-light'));
    await t.tap(find.text('Later'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    await t.pumpWidget(host(LookoutTheme.dark()));
    await t.tap(find.text('Check for updates'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Lookout 1.1.20 is available'), findsOneWidget);
    await t.runAsync(() => _shot(rootKey, 'v1118-dialog-dark'));
  });
}
