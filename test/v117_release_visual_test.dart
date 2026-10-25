import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lookout/presentation/source_review_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/source_discovery.dart';
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

/// Serves the REAL live feed body (copied from the served update.json) for
/// update/none cases, or throws for the failure case.
class _FeedClient extends http.BaseClient {
  _FeedClient(this.mode);
  final String mode; // 'update' | 'same' | 'fail'
  static const feedBody =
      '{"lookout":{"version":"1.1.10","notes":"The app can no longer get stuck on the logo at startup: a failing startup step now says on screen what failed and why. Notification or scheduling problems no longer block the app and are shown instead. Includes 1.1.9: honest task history, reliable background checks, readable update dialog, Bitcoin source discovery.","apk":"https://lookout-apk.pages.dev/Lookout-v1.1.10.apk"}}';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (mode == 'fail') throw const SocketException('offline');
    return http.StreamedResponse(
      Stream.value(utf8.encode(feedBody)),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

UpdateChecker _checker(String mode, String current) => UpdateChecker(
      client: _FeedClient(mode),
      currentVersion: () async => current,
      canInstall: () async => true,
    );

void main() {
  testWidgets('v1.1.7 updater UI (real control flow) + live discovery',
      (t) async {
    await t.runAsync(() async {
      await Directory('/tmp/lookout-shots').create(recursive: true);
      await _loadFonts();
      HttpOverrides.global = null; // real dart:io networking for discovery
    });
    SharedPreferences.setMockInitialValues({});
    debugRunUpdateChecksInTests = true;
    addTearDown(() => debugRunUpdateChecksInTests = false);
    await t.binding.setSurfaceSize(const Size(390, 844));
    final rootKey = GlobalKey();

    Widget host({
      required ThemeData theme,
      required String label,
      required Future<void> Function(BuildContext) onTap,
    }) {
      return RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            appBar: AppBar(title: const Text('Lookout')),
            body: Center(
              child: Builder(
                builder: (ctx) => FilledButton(
                  onPressed: () => onTap(ctx),
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 1. Manual check, update branch (real checkUpdateManually -> real
    // dialog), LIGHT theme - the contrast-fix render.
    await t.pumpWidget(host(
      theme: LookoutTheme.light(),
      label: 'Check for updates',
      onTap: (ctx) =>
          checkUpdateManually(ctx, checker: _checker('update', '1.1.6')),
    ));
    await t.tap(find.text('Check for updates'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Lookout 1.1.10 is available'), findsOneWidget);
    await t.runAsync(() => _shot(rootKey, 'v1110-dialog-light-manual'));
    await t.tap(find.text('Later'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // 2. Auto check branch (real maybePromptUpdate), DARK theme - confirms
    // no regression where the dialog was designed for.
    await t.pumpWidget(host(
      theme: LookoutTheme.dark(),
      label: 'auto',
      onTap: (ctx) =>
          maybePromptUpdate(ctx, checker: _checker('update', '1.1.6')),
    ));
    await t.tap(find.text('auto'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Lookout 1.1.10 is available'), findsOneWidget);
    await t.runAsync(() => _shot(rootKey, 'v1110-dialog-dark-auto'));
    await t.tap(find.text('Later'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));

    // 3. Manual check, failure branch (real function, client offline).
    await t.pumpWidget(host(
      theme: LookoutTheme.light(),
      label: 'Check for updates',
      onTap: (ctx) =>
          checkUpdateManually(ctx, checker: _checker('fail', '1.1.6')),
    ));
    await t.tap(find.text('Check for updates'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Could not check for updates. Try again later.'),
        findsOneWidget);
    await t.runAsync(() => _shot(rootKey, 'v1110-manual-check-error'));
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 400));

    // 4. Manual check, up-to-date branch (real function, same version).
    await t.pumpWidget(host(
      theme: LookoutTheme.light(),
      label: 'Check for updates',
      onTap: (ctx) =>
          checkUpdateManually(ctx, checker: _checker('same', '1.1.10')),
    ));
    await t.tap(find.text('Check for updates'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('No update available'), findsOneWidget);
    await t.runAsync(() => _shot(rootKey, 'v1110-manual-check-none'));
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 400));

    // 5. REAL live discovery populating the production review screen.
    await t.binding.setSurfaceSize(const Size(390, 1500));
    await t.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          theme: LookoutTheme.light(),
          home: const SourceReviewScreen(
            task: 'watch bitcoin under \$90000',
            discovery: SourceDiscoveryService(
              searchProvider: TavilyKeylessSearch(),
              pageReader: HttpDiscoveryPageReader(),
            ),
          ),
        ),
      ),
    );
    await t.pump();
    final dropdowns = find.byType(DropdownButtonFormField<String>);
    await t.tap(dropdowns.at(0));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('United States').last);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(dropdowns.at(1));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.textContaining('USD —').last);
    await t.pump(const Duration(milliseconds: 400));
    var populated = false;
    for (var attempt = 0; attempt < 2 && !populated; attempt++) {
      await t.runAsync(() async {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 15));
        }
        final btn = t.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Find matching pages'));
        btn.onPressed!();
        await Future<void>.delayed(const Duration(seconds: 18));
      });
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      populated = find
              .textContaining('Source search is unavailable')
              .evaluate()
              .isEmpty &&
          find
              .textContaining('Source search could not be completed')
              .evaluate()
              .isEmpty;
    }
    await t.pump(const Duration(milliseconds: 500));
    print('DISCOVERY UI: coingecko='
        '${find.textContaining('coingecko').evaluate().isNotEmpty} coinbase='
        '${find.textContaining('coinbase').evaluate().isNotEmpty}');
    await t.runAsync(() => _shot(rootKey, 'v1110-bitcoin-discovery-review'));
    expect(t.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
