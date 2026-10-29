import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/presentation/source_review_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/source_discovery.dart';

/// Renders the source review flow with a proven readable-quote candidate -
/// the release evidence that a gold task finds a source without pasting.
class _GoldDiscovery implements SourceDiscoveryService {
  @override
  final DiscoveryPageReader pageReader = _NoReader();
  @override
  final SourceSearchProvider searchProvider = _NoSearch();
  @override
  Future<DiscoveryResult> discover(DiscoverySpec spec) async {
    return DiscoveryResult([
      SourceCandidate(
        url: Uri.parse('https://goldpricez.com/us/ounce'),
        product: 'Gold Price Today in United States in U.S. Dollar per Ounce',
        price: 4022.28,
        currency: 'USD',
        country: 'United States',
        checkedAt: DateTime(2026, 10, 29, 15, 0),
        marketQuote: true,
        readableQuote: true,
      ),
    ]);
  }

  @override
  Future<SourceCandidate?> revalidate(
    DiscoverySpec spec,
    SourceCandidate selected, {
    DateTime? now,
  }) async =>
      selected;
}

class _NoReader implements DiscoveryPageReader {
  @override
  Future<ProductPage> read(Uri url) => throw StateError('unused');
}

class _NoSearch implements SourceSearchProvider {
  @override
  Future<List<SearchPage>> search(DiscoverySpec spec) async => const [];
}

ThemeData _withFont(ThemeData base) => base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    );

void main() {
  testWidgets('v1.1.18 review flow shows the proven gold quote source',
      (t) async {
    // Real glyphs, not harness boxes: render proof must be readable. Both
    // fonts ship inside the Flutter SDK cache, so this resolves everywhere
    // the SDK runs, including CI.
    await t.runAsync(() async {
      final root = Platform.environment['FLUTTER_ROOT'] ?? '/tmp/flutter';
      final fonts = '$root/bin/cache/artifacts/material_fonts';
      for (final entry in {
        'Roboto': '$fonts/Roboto-Regular.ttf',
        'MaterialIcons': '$fonts/MaterialIcons-Regular.otf',
      }.entries) {
        final bytes = File(entry.value).readAsBytesSync();
        final loader = FontLoader(entry.key)
          ..addFont(Future.value(ByteData.sublistView(bytes)));
        await loader.load();
      }
    });
    await t.binding.setSurfaceSize(const Size(390, 1500));
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: _withFont(LookoutTheme.light()),
        home: RepaintBoundary(
          key: key,
          child: SourceReviewScreen(
            task: 'Tell me when Gold Price rises above 4030',
            discovery: _GoldDiscovery(),
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
    await t.runAsync(() async {
      final btn = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Find matching pages'),
      );
      btn.onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    expect(find.textContaining('goldpricez.com'), findsWidgets);
    expect(find.textContaining('confirm'), findsWidgets);
    await t.runAsync(() async {
      final im = await (key.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage(pixelRatio: 2);
      final d = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/lookout-shots/v1118-source-review.png')
          .writeAsBytes(d!.buffer.asUint8List());
    });
  });
}
