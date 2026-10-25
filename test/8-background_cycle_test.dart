import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/background.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/page_fetch.dart';

Agent reminder({required DateTime due, int? id}) => Agent(
      id: id,
      title: 'r',
      originalPrompt: 'p',
      type: AgentType.reminder,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 1, 1),
      checkInterval: const Duration(minutes: 15),
      condition: WatchCondition.remindAt,
      target: due.millisecondsSinceEpoch.toDouble(),
    );

Agent slowWatch({int? id, DateTime? next}) => Agent(
      id: id,
      title: 'w$id',
      originalPrompt: 'p',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 1, 1),
      checkInterval: const Duration(hours: 1),
      condition: WatchCondition.lessThan,
      target: 100,
      currentValue: 200,
      sourceUrl: 'https://example.com/item',
      nextCheckAt: next,
    );

class RecordingRepo extends InMemoryAgentRepository {
  final kvOrder = <String>[];
  @override
  Future<void> putKv(String key, String value) async {
    kvOrder.add(key);
    return super.putKv(key, value);
  }
}

class FailingRepo extends InMemoryAgentRepository {
  @override
  Future<List<Agent>> dueAgents(DateTime now) =>
      throw StateError('store exploded');
}

void main() {
  test('started marker lands before the completion marker', () async {
    final repo = RecordingRepo();
    final now = DateTime(2026, 1, 2, 12);
    await repo.insertAgent(reminder(due: now.subtract(const Duration(hours: 1))));
    final checker =
        AgentChecker(repo: repo, notifier: RecordingNotifier(), clock: () => now);
    final ok = await runBackgroundCycle(repo: repo, checker: checker);
    expect(ok, isTrue);
    final started = await repo.getKv('lastBackgroundRunStartedAt');
    final completed = await repo.getKv('lastBackgroundRunAt');
    expect(started, isNotNull);
    expect(completed, isNotNull);
    expect(
      repo.kvOrder.indexOf('lastBackgroundRunStartedAt'),
      lessThan(repo.kvOrder.indexOf('lastBackgroundRunAt')),
    );
    expect(await repo.getKv('lastBackgroundRunChecked'), '1');
    expect(await repo.getKv('lastBackgroundError'), isNull);
  });

  test('a failing sweep records an error and returns false', () async {
    final repo = FailingRepo();
    final checker = AgentChecker(repo: repo, notifier: RecordingNotifier());
    final ok = await runBackgroundCycle(repo: repo, checker: checker);
    expect(ok, isFalse);
    expect(await repo.getKv('lastBackgroundRunStartedAt'), isNotNull);
    expect(await repo.getKv('lastBackgroundRunAt'), isNull);
    expect(await repo.getKv('lastBackgroundError'), contains('store exploded'));
  });

  test('budget-exhausted sweep reports partial progress honestly', () async {
    final repo = InMemoryAgentRepository();
    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      await repo.insertAgent(
          slowWatch(next: now.subtract(Duration(hours: 3 - i))));
    }
    final checker = AgentChecker(
      repo: repo,
      notifier: RecordingNotifier(),
      fetcher: (url) async {
        await Future.delayed(const Duration(milliseconds: 120));
        return FetchOutcome.failed('slow host');
      },
    );
    final result = await checker.checkDueAgents(
      timeBudget: const Duration(milliseconds: 50),
    );
    expect(result.budgetExhausted, isTrue);
    expect(result.checked, lessThan(3));
    expect(result.totalDue, 3);
    // Unchecked tasks stay due: the next sweep with a real budget serves
    // the rest.
    final second = await checker.checkDueAgents();
    expect(second.checked, 3 - result.checked);
    expect(second.budgetExhausted, isFalse);
  });

  test('overlapping sweeps never double-run checks', () async {
    final repo = InMemoryAgentRepository();
    final now = DateTime.now();
    await repo.insertAgent(slowWatch(next: now.subtract(const Duration(hours: 1))));
    final checker = AgentChecker(
      repo: repo,
      notifier: RecordingNotifier(),
      fetcher: (url) async {
        await Future.delayed(const Duration(milliseconds: 150));
        return FetchOutcome.failed('slow host');
      },
    );
    final first = checker.checkDueAgents();
    final second = await checker.checkDueAgents();
    expect(second.skippedBusy, isTrue);
    final firstResult = await first;
    expect(firstResult.checked, 1);
    final log = await repo.activityFor(1);
    expect(
      log.where((e) => e.message == 'Started check').length,
      1,
    );
  });
}
