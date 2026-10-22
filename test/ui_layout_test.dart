import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/agent_details_screen.dart';
import 'package:lookout/presentation/create_agent_screen.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/presentation/theme.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';

Agent sample() => Agent(
  title: 'A long watch title that must wrap without hiding the goal',
  originalPrompt: 'below 500',
  type: AgentType.valueWatch,
  status: AgentStatus.active,
  createdAt: DateTime(2026, 10, 15),
  checkInterval: const Duration(minutes: 30),
  condition: WatchCondition.lessThan,
  target: 500,
  currentValue: 550,
  sourceUrl: 'https://example.com/item',
);

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(800, 1000),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('home/create/details layout ${size.width} scale $scale', (
        t,
      ) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        final repo = InMemoryAgentRepository();
        final id = await repo.insertAgent(sample());
        final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
        for (final page in [
          HomeScreen(repo: repo, checker: checker),
          CreateAgentScreen(repo: repo),
          AgentDetailsScreen(repo: repo, checker: checker, agentId: id),
        ]) {
          await t.pumpWidget(
            MaterialApp(
              theme: LookoutTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: page,
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await t.drag(find.byType(ListView).first, const Offset(0, -1600));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
      });
    }
  }
  testWidgets('examples still create the original supported reminder', (
    t,
  ) async {
    final repo = InMemoryAgentRepository();
    await t.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          repo: repo,
          checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Create Agent'));
    await t.pumpAndSettle();
    await t.tap(find.text('Set a reminder'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Create Agent'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.widgetWithText(FilledButton, 'Create Agent'));
    await t.pumpAndSettle();
    final agents = await repo.allAgents();
    expect(agents.length, 1);
    expect(agents.single.type, AgentType.reminder);
    expect(agents.single.status, AgentStatus.active);
    expect(agents.single.checkInterval, const Duration(minutes: 30));
  });
  testWidgets(
    'details retains Run now and pause/resume; UI opens without writes',
    (t) async {
      final repo = InMemoryAgentRepository();
      final id = await repo.insertAgent(sample());
      await t.pumpWidget(
        MaterialApp(
          home: AgentDetailsScreen(
            repo: repo,
            checker: AgentChecker(repo: repo, notifier: RecordingNotifier()),
            agentId: id,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect((await repo.agentById(id))!.status, AgentStatus.active);
      expect(find.text('Run now'), findsOneWidget);
      await t.tap(find.text('Pause'));
      await t.pumpAndSettle();
      expect((await repo.agentById(id))!.status, AgentStatus.paused);
      await t.tap(find.text('Resume'));
      await t.pumpAndSettle();
      expect((await repo.agentById(id))!.status, AgentStatus.active);
    },
  );
}
