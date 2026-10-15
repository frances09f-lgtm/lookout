// Rendered Flutter review captures. ALL offers are synthetic test fixtures.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/source_review_screen.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/source_discovery.dart';

import 'next_update_test.dart' as fixture;

const out = String.fromEnvironment('CAPTURE_DIR');
Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
  if (out.isEmpty) return;
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$out/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.pumpAndSettle();
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

// Resolve fonts from this checkout's actual Flutter SDK, including CI.
String flutterMaterialFontsPath() {
  final config = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(config.readAsStringSync())
              as Map<String, dynamic>)['packages']
          as List;
  final flutter = packages.cast<Map<String, dynamic>>().firstWhere(
    (p) => p['name'] == 'flutter',
  );
  final packageRoot = config.uri.resolve('${flutter['rootUri']}/');
  return Directory.fromUri(
    packageRoot.resolve('../../bin/cache/artifacts/material_fonts/'),
  ).path;
}

Future<void> fonts(WidgetTester t) async {
  await t.runAsync(() async {
    final icon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icon.load();
    final path = flutterMaterialFontsPath();
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            await File('$path/Roboto-$weight.ttf').readAsBytes(),
          ),
        ),
      );
    }
    await loader.load();
  });
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'final rendered compact and fixture source flow ${dark ? 'dark' : 'light'}',
      (t) async {
        await fonts(t);
        await t.binding.setSurfaceSize(const Size(336, 750));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final key = GlobalKey();
        final nav = GlobalKey<NavigatorState>();
        final repo = InMemoryAgentRepository();
        final service = SourceDiscoveryService(
          searchProvider: fixture.FakeSearch(),
          pageReader: fixture.FakeReader(fixture.fixture()),
        );
        final mode = dark ? 'dark' : 'light';
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
            builder: (_, child) => RepaintBoundary(key: key, child: child!),
            home: CreateAgentScreen(repo: repo, discovery: service),
          ),
        );
        await capture(t, key, '01-create-$mode');
        final left = t.getRect(find.text('Watch a value'));
        final right = t.getRect(find.text('Set a reminder'));
        expect((left.top - right.top).abs(), lessThan(1));
        expect(left.left, lessThan(right.left));
        // Actual widget interaction, not a reconstructed mockup.
        await t.enterText(
          find.byType(TextField).first,
          'check iphone price below 60000',
        );
        await tap(t, find.text('Find matching source'));
        expect(find.byType(SourceReviewScreen), findsOneWidget);
        await tap(t, find.text('Find matching pages'));
        expect(find.textContaining('Which iPhone model'), findsOneWidget);
        // Questions at the bottom; scroll to them for a readable clarification capture.
        await t.scrollUntilVisible(
          find.textContaining('Which iPhone model'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await capture(t, key, '02-clarify-$mode');
        await t.drag(find.byType(ListView).first, const Offset(0, 1500));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byType(TextField).first);
        await t.enterText(
          find.byType(TextField).first,
          'check iphone 15 black 128GB price below 60000',
        );
        await tap(t, find.byType(DropdownButtonFormField<String>).at(0));
        await tap(t, find.text('India').last);
        await tap(t, find.byType(DropdownButtonFormField<String>).at(1));
        await tap(t, find.text('INR — ₹').last);
        await tap(t, find.text('Find matching pages'));
        await tap(t, find.text('Apple iPhone 15 128GB Black'));
        await t.scrollUntilVisible(
          find.text('Use this source'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await capture(t, key, '03-review-FIXTURE-$mode');
        expect(await repo.allAgents(), isEmpty);
        await tap(t, find.text('Use this source'));
        expect(find.text('Reviewed source'), findsOneWidget);
        expect(await repo.allAgents(), isEmpty);
        await t.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Create Agent'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await capture(t, key, '04-ready-FIXTURE-$mode');
        await tap(t, find.widgetWithText(FilledButton, 'Create Agent'));
        final agent = (await repo.allAgents()).single;
        expect(agent.sourceIdentity, isNotNull);
        // Root Create has no route below it, so inspect saved state through the real details screen.
        nav.currentState!.push(
          MaterialPageRoute(
            builder: (_) => AgentDetailsScreen(
              repo: repo,
              checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
              agentId: agent.id!,
              discovery: service,
            ),
          ),
        );
        await capture(t, key, '05-created-FIXTURE-$mode');
        expect(t.takeException(), isNull);
      },
    );
  }
}
