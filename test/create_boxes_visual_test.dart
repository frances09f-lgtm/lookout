import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/page_fetch.dart';
import 'test_fonts.dart';


void main() {
  testWidgets('boxes compose the same task the parser already handles',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    await t.pumpWidget(
      MaterialApp(theme: LookoutTheme.light(), home: CreateAgentScreen(repo: repo)),
    );
    await t.pumpAndSettle();
    expect(find.text('PRODUCT'), findsOneWidget);
    expect(find.text('TARGET'), findsOneWidget);
    expect(find.text('LINK'), findsOneWidget);
    expect(find.text('Test link'), findsOneWidget);

    await t.enterText(
      find.byType(TextField).at(0),
      'boAt Airdopes 141',
    );
    await t.enterText(find.byType(TextField).at(1), '1299');
    await t.pumpAndSettle();
    // Review-before-create: the schedule block stays hidden behind the
    // green Review watch CTA until the user asks for it.
    expect(find.text('Review & schedule'), findsNothing);
    await t.tap(find.widgetWithText(FilledButton, 'Review watch'));
    await t.pumpAndSettle();
    expect(find.text('Review & schedule'), findsOneWidget);
    expect(find.textContaining('below 1299.0'), findsOneWidget);
    expect(find.text('Create Agent'), findsOneWidget);

    // Condition switch to "Rises above" recomposes the task.
    await t.tap(find.text('Drops below'));
    await t.pumpAndSettle();
    await t.tap(find.text('Rises above').last);
    await t.pumpAndSettle();
    // Editing a box hides the review again until re-approved.
    expect(find.text('Review & schedule'), findsNothing);
    await t.tap(find.widgetWithText(FilledButton, 'Review watch'));
    await t.pumpAndSettle();
    expect(find.textContaining('above 1299.0'), findsOneWidget);

    // Reminder / text-watch entry point switches to the describe flow.
    await t.scrollUntilVisible(
      find.text('Set a reminder or watch text on a page instead'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Set a reminder or watch text on a page instead'));
    await t.pumpAndSettle();
    expect(find.text('One less thing\nto keep checking.'), findsOneWidget);
    expect(find.text('Watch for text on a public page'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('selected unit survives compose, review and the stored watch',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    await t.pumpWidget(
      MaterialApp(theme: LookoutTheme.light(), home: CreateAgentScreen(repo: repo)),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(0), 'Bitcoin');
    await t.tap(find.byType(DropdownButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('\$').last);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(1), '80000');
    await t.enterText(find.byType(TextField).at(2), 'https://example.com/btc');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Review watch'));
    await t.pumpAndSettle();
    // The review step shows the composed text with the selected unit.
    expect(find.textContaining('drops below \$80000'), findsWidgets);
    await t.tap(find.widgetWithText(FilledButton, 'Create Agent'));
    await t.pumpAndSettle();
    final agents = await repo.allAgents();
    expect(agents, hasLength(1));
    expect(agents.single.originalPrompt, contains('\$80000'));
    expect(agents.single.condition, WatchCondition.lessThan);
    expect(agents.single.target, 80000);
    expect(agents.single.sourceUrl, 'https://example.com/btc');
    // New watches default to hourly checks.
    expect(agents.single.checkInterval, const Duration(hours: 1));
    expect(t.takeException(), isNull);
  });

  testWidgets('test link shows loading, then the read with honest limits',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    PageValueFetcher.debugFetchValue = (url) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return FetchOutcome.found(80100.5, 'Found 80100.5 on example.com');
    };
    addTearDown(() => PageValueFetcher.debugFetchValue = null);
    await t.pumpWidget(
      MaterialApp(theme: LookoutTheme.light(), home: CreateAgentScreen(repo: repo)),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(2), 'https://example.com/btc');
    await t.pumpAndSettle();
    await t.tap(find.text('Test link'));
    await t.pump();
    expect(find.text('Reading the page…'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('Read 80100.5'), findsOneWidget);
    expect(find.textContaining('Found 80100.5 on example.com'), findsOneWidget);
    expect(find.textContaining('Read once just now'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('test link surfaces reader errors verbatim, never a price',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    PageValueFetcher.debugFetchValue =
        (url) async => FetchOutcome.failed('Could not fetch page (HTTP 403)');
    addTearDown(() => PageValueFetcher.debugFetchValue = null);
    await t.pumpWidget(
      MaterialApp(theme: LookoutTheme.light(), home: CreateAgentScreen(repo: repo)),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(2), 'https://example.com/blocked');
    await t.pumpAndSettle();
    await t.tap(find.text('Test link'));
    await t.pumpAndSettle();
    expect(find.textContaining('Could not fetch page (HTTP 403)'), findsOneWidget);
    expect(find.textContaining('Read 4'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('amazon links are blocked from testing as unreliable', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    var fetchCalled = false;
    PageValueFetcher.debugFetchValue = (url) async {
      fetchCalled = true;
      return FetchOutcome.found(12023, 'EMI-looking value');
    };
    addTearDown(() => PageValueFetcher.debugFetchValue = null);
    await t.pumpWidget(
      MaterialApp(theme: LookoutTheme.light(), home: CreateAgentScreen(repo: repo)),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byType(TextField).at(2),
      'https://www.amazon.in/dp/B0CHX1W1XY',
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Test link'));
    await t.pumpAndSettle();
    expect(fetchCalled, isFalse);
    expect(
      find.textContaining('Amazon pages cannot be tested reliably'),
      findsOneWidget,
    );
    expect(find.textContaining('EMI amount'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  for (final dark in [true, false]) {
    testWidgets('create boxes render (dark=$dark)', (t) async {
      await t.runAsync(() async {
        await Directory('/tmp/lookout-shots').create(recursive: true);
        await loadTestFonts();
      });
      final repo = InMemoryAgentRepository();
      addTearDown(repo.close);
      await t.binding.setSurfaceSize(const Size(390, 1600));
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: dark ? LookoutTheme.dark() : LookoutTheme.light(),
          home: RepaintBoundary(
            key: key,
            child: CreateAgentScreen(repo: repo),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(0), 'boAt Airdopes 141');
      await t.enterText(find.byType(TextField).at(1), '1,299');
      await t.enterText(
        find.byType(TextField).at(2),
        'https://www.amazon.in/dp/B0C7QH7L36',
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final im =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1.5);
        final d = await im.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/lookout-shots/create-boxes-${dark ? 'dark' : 'light'}.png',
        ).writeAsBytes(d!.buffer.asUint8List());
      });
    });
  }
}
