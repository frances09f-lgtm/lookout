import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';

Agent reminder({required DateTime due, int id = 1}) => Agent(
      id: id,
      title: 'Test reminder',
      originalPrompt: 'remind me',
      type: AgentType.reminder,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 1, 1),
      checkInterval: const Duration(minutes: 15),
      condition: WatchCondition.remindAt,
      target: due.millisecondsSinceEpoch.toDouble(),
    );

void main() {
  test('due reminder completes and notifies', () async {
    final repo = InMemoryAgentRepository();
    final notifier = RecordingNotifier();
    final now = DateTime(2026, 1, 2, 12);
    final a = reminder(due: DateTime(2026, 1, 2, 11));
    final id = await repo.insertAgent(a);
    final checker = AgentChecker(
        repo: repo, notifier: notifier, clock: () => now);
    final count = await checker.checkDueAgents();
    expect(count, 1);
    expect(notifier.shown, hasLength(1));
    final stored = await repo.agentById(id);
    expect(stored!.status, AgentStatus.completed);
    final log = await repo.activityFor(id);
    expect(log.map((e) => e.message),
        containsAll(<String>['Started check', 'Condition met', 'Notification sent', 'Agent completed']));
  });

  test('future reminder reschedules without notifying', () async {
    final repo = InMemoryAgentRepository();
    final notifier = RecordingNotifier();
    final now = DateTime(2026, 1, 2, 12);
    final id = await repo.insertAgent(reminder(due: now.add(const Duration(hours: 1))));
    final checker = AgentChecker(repo: repo, notifier: notifier, clock: () => now);
    await checker.checkDueAgents();
    expect(notifier.shown, isEmpty);
    final stored = await repo.agentById(id);
    expect(stored!.status, AgentStatus.active);
    expect(stored.lastCheckedAt, now);
    expect(stored.nextCheckAt, now.add(const Duration(minutes: 15)));
  });

  test('value watch fires when below target', () async {
    final repo = InMemoryAgentRepository();
    final notifier = RecordingNotifier();
    final id = await repo.insertAgent(Agent(
      id: 7,
      title: 'Laptop',
      originalPrompt: 'cheaper than 50000',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 1, 1),
      checkInterval: const Duration(minutes: 30),
      condition: WatchCondition.lessThan,
      target: 50000,
      currentValue: 47500,
    ));
    final checker = AgentChecker(repo: repo, notifier: notifier, clock: () => DateTime(2026, 1, 2));
    await checker.checkDueAgents();
    expect(notifier.shown, hasLength(1));
    expect((await repo.agentById(id))!.status, AgentStatus.completed);
  });

  test('value watch without a value stays active and waits', () async {
    final repo = InMemoryAgentRepository();
    final notifier = RecordingNotifier();
    final id = await repo.insertAgent(Agent(
      id: 9,
      title: 'Laptop',
      originalPrompt: 'cheaper than 50000',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 1, 1),
      checkInterval: const Duration(minutes: 30),
      condition: WatchCondition.lessThan,
      target: 50000,
    ));
    final checker = AgentChecker(repo: repo, notifier: notifier, clock: () => DateTime(2026, 1, 2));
    await checker.checkDueAgents();
    expect(notifier.shown, isEmpty);
    final stored = await repo.agentById(id);
    expect(stored!.status, AgentStatus.active);
    final log = await repo.activityFor(id);
    expect(log.any((e) => e.message.contains('No source page set and no manual value')), isTrue);
  });

  test('paused agents are not checked', () async {
    final repo = InMemoryAgentRepository();
    final notifier = RecordingNotifier();
    await repo.insertAgent(reminder(due: DateTime(2026, 1, 1))
        .copyWith(status: AgentStatus.paused));
    final checker = AgentChecker(repo: repo, notifier: notifier, clock: () => DateTime(2026, 1, 2));
    expect(await checker.checkDueAgents(), 0);
    expect(notifier.shown, isEmpty);
  });
}
