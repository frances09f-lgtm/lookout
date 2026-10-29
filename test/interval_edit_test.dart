import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';

Agent watch(AgentStatus status) => Agent(
  title: 'iPhone 15',
  originalPrompt: 'iphone 15 below 60000',
  type: AgentType.valueWatch,
  status: status,
  createdAt: DateTime(2026, 1, 1),
  checkInterval: const Duration(minutes: 30),
  condition: WatchCondition.lessThan,
  target: 60000,
  currentValue: 67999,
  sourceUrl: 'https://shop.example.com/product',
);

void main() {
  testWidgets('details edits the check interval and reschedules from now',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final id = await repo.insertAgent(watch(AgentStatus.active));
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await t.pumpWidget(
      MaterialApp(
        home: AgentDetailsScreen(repo: repo, checker: checker, agentId: id),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Check every'), findsOneWidget);
    expect(
      find.textContaining('5 and 10-minute checks are attempted while the app is open'),
      findsOneWidget,
    );
    // Save stays disabled until the selection actually changes.
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save interval'),
          )
          .onPressed,
      isNull,
    );
    await t.tap(find.text('10 min'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save interval'));
    await t.pumpAndSettle();
    final saved = (await repo.agentById(id))!;
    expect(saved.checkInterval, const Duration(minutes: 10));
    expect(
      saved.nextCheckAt!.isAfter(
        DateTime.now().add(const Duration(minutes: 9)),
      ),
      isTrue,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('completed watches keep a plain interval row, no editor',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = InMemoryAgentRepository();
    addTearDown(repo.close);
    final id = await repo.insertAgent(watch(AgentStatus.completed));
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await t.pumpWidget(
      MaterialApp(
        home: AgentDetailsScreen(repo: repo, checker: checker, agentId: id),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Save interval'), findsNothing);
    expect(find.textContaining('every 30 min'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
