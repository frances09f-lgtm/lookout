// Real Flutter widget captures of synthetic public-page and product fixtures.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/source_review_screen.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/source_discovery.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';

import 'general_discovery_test.dart' as general;
import 'next_update_test.dart' as h;
import 'recovery_capture_test.dart' as capture;

void main() {
  for (final category in ['price', 'results', 'announcement']) {
    testWidgets(
      'general task $category: UI review, explicit activation and check',
      (t) async {
        await capture.fonts(t);
        await t.binding.setSurfaceSize(const Size(336, 750));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final key = GlobalKey();
        final nav = GlobalKey<NavigatorState>();
        final repo = InMemoryAgentRepository();
        final task = category == 'price'
            ? 'Check Sony WH-1000XM5 price below 25000'
            : category == 'results'
            ? general.resultTask
            : 'Check Example Space Agency announcements contains "Launch scheduled"';
        final spec = category == 'price'
            ? general.price('Sony WH-1000XM5')
            : general.text(task);
        final product = category == 'price'
            ? h.fixture(name: 'Sony WH-1000XM5', price: 24000)
            : general.page(
                spec.model,
                'This public fixture page is regularly updated. Please return for the next announcement.',
              );
        final service = SourceDiscoveryService(
          searchProvider: general.Search(product),
          pageReader: h.FakeReader(product),
        );
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            theme: LookoutTheme.dark(),
            builder: (_, child) => RepaintBoundary(key: key, child: child!),
            home: CreateAgentScreen(repo: repo, discovery: service),
          ),
        );
        if (category == 'results') {
          await capture.capture(t, key, '01-general-create-dark');
        }
        await t.enterText(find.byType(TextField).first, task);
        await capture.tap(t, find.text('Find matching source'));
        expect(find.byType(SourceReviewScreen), findsOneWidget);
        if (category == 'price') {
          await capture.tap(
            t,
            find.byType(DropdownButtonFormField<String>).at(0),
          );
          await capture.tap(t, find.text('India').last);
          await capture.tap(
            t,
            find.byType(DropdownButtonFormField<String>).at(1),
          );
          await capture.tap(t, find.text('INR — ₹').last);
        } else {
          expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        }
        await capture.tap(t, find.text('Find matching pages'));
        expect(await repo.allAgents(), isEmpty);
        await capture.tap(
          t,
          find.text(category == 'price' ? 'Sony WH-1000XM5' : spec.model),
        );
        await t.scrollUntilVisible(
          find.text('Use this source'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await capture.capture(t, key, '02-$category-review-FIXTURE');
        await capture.tap(t, find.text('Use this source'));
        expect(await repo.allAgents(), isEmpty);
        await capture.tap(t, find.widgetWithText(FilledButton, 'Create Agent'));
        var a = (await repo.allAgents()).single;
        expect(a.isTextWatch, category != 'price');
        final checker = AgentChecker(
          repo: repo,
          notifier: RecordingNotifier(),
          strictFetcher: (a) =>
              DiscoveredSourceReader.fetch(a, reader: h.FakeReader(product)),
        );
        final checked = await checker.checkAgent(a);
        expect(checked.evaluated, true);
        expect(checked.conditionMet, category == 'price');
        a = (await repo.agentById(a.id!))!;
        nav.currentState!.push(
          MaterialPageRoute(
            builder: (_) => AgentDetailsScreen(
              repo: repo,
              checker: checker,
              agentId: a.id!,
              discovery: service,
            ),
          ),
        );
        await capture.capture(t, key, '03-$category-checked-FIXTURE');
        if (category != 'price') {
          expect(find.text('Update current value'), findsNothing);
          expect(find.text('Edit target'), findsNothing);
          expect(find.text('Set source page'), findsNothing);
        }
        expect(t.takeException(), isNull);
      },
    );
  }
}
