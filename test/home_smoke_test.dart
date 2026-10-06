import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/presentation/home_screen.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';

void main() {
  testWidgets('home renders empty state and summary', (tester) async {
    final repo = InMemoryAgentRepository();
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await tester.pumpWidget(MaterialApp(home: HomeScreen(repo: repo, checker: checker)));
    await tester.pumpAndSettle();
    expect(find.text('Lookout'), findsOneWidget);
    expect(find.text('Create Agent'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining('No agents yet'), findsOneWidget);
  });

  testWidgets('home lists an agent card', (tester) async {
    final repo = InMemoryAgentRepository();
    await repo.insertAgent(Agent(
      title: 'Laptop watch', originalPrompt: 'p', type: AgentType.valueWatch,
      status: AgentStatus.active, createdAt: DateTime(2026, 1, 1),
      checkInterval: const Duration(minutes: 30),
      condition: WatchCondition.lessThan, target: 50000, currentValue: 52000,
    ));
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    await tester.pumpWidget(MaterialApp(home: HomeScreen(repo: repo, checker: checker)));
    await tester.pumpAndSettle();
    expect(find.text('Laptop watch'), findsOneWidget);
    expect(find.text('Run now'), findsOneWidget);
  });
}
