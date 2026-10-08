import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/theme.dart';

void main() {
  testWidgets('product discovery preview shows threshold and no pasted-link selection', (
    t,
  ) async {
    await t.runAsync(() async {
      final f = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
      final l = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
      await l.load();
    });
    await t.runAsync(() async {
      final f = File(
        '${Platform.environment['FLUTTER_ROOT'] ?? '/home/sandbox/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (!await f.exists()) return;
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(await f.readAsBytes())));
      await loader.load();
    });
    await t.binding.setSurfaceSize(const Size(412, 1000));
    final k = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: LookoutTheme.dark(),
          home: CreateAgentScreen(repo: InMemoryAgentRepository()),
        ),
      ),
    );
    await t.enterText(
      find.byType(TextField).first,
      'watch iPhone 16 128 GB price below 60000',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('Parsed threshold: below 60000.0'), findsOneWidget);
    expect(find.text('Find product source'), findsOneWidget);

    await t.runAsync(() async {
      final im =
          await (k.currentContext!.findRenderObject() as RenderRepaintBoundary)
              .toImage();
      final b = await im.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/lookout-discovery-preview.png')
          .writeAsBytes(b!.buffer.asUint8List());
    });
  });
}
