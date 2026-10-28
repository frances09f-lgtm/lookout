import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/background.dart';
import 'package:lookout/services/notifications.dart';

class CloseCountingRepo extends InMemoryAgentRepository {
  int closeCalls = 0;
  @override
  Future<void> close() async {
    closeCalls++;
  }
}

class BrokenStoreRepo extends InMemoryAgentRepository {
  @override
  Future<List<Agent>> dueAgents(DateTime now) =>
      throw StateError('store exploded');
}

void main() {
  // Lifecycle of one Workmanager task: the worker closes only the store it
  // opened. That is safe because SqfliteAgentRepository.open passes
  // singleInstance: false, so the close never touches the foreground app's
  // connection - closing the formerly shared one was the v1.1.13
  // database_closed failure (tekartik/sqflite#558; the cross-connection
  // regression itself is covered in db_closed_test.dart).
  test('a successful task run closes only its own store', () async {
    final repo = CloseCountingRepo();
    final now = DateTime.now();
    await repo.insertAgent(Agent(
      title: 'r', originalPrompt: 'p', type: AgentType.reminder,
      status: AgentStatus.active, createdAt: now,
      checkInterval: const Duration(minutes: 15),
      condition: WatchCondition.remindAt,
      target: now.millisecondsSinceEpoch.toDouble(),
      nextCheckAt: now.subtract(const Duration(minutes: 1)),
    ));
    final ok = await runWorkmanagerTask(
      openRepo: () async => repo,
      makeNotifier: () async => RecordingNotifier(),
    );
    expect(ok, isTrue);
    expect(repo.closeCalls, 1);
    expect(await repo.getKv('lastBackgroundRunAt'), isNotNull);
  });

  test('a failing task run records the error and closes its store', () async {
    final repo = BrokenStoreRepo();
    final ok = await runWorkmanagerTask(
      openRepo: () async => repo,
      makeNotifier: () async => RecordingNotifier(),
    );
    expect(ok, isFalse);
    expect(await repo.getKv('lastBackgroundError'), contains('store exploded'));
    expect(repo.closeCalls, 1);
  });

  test('a store that cannot open still reports failure honestly', () async {
    final ok = await runWorkmanagerTask(
      openRepo: () => throw StateError('open wedged'),
      makeNotifier: () async => RecordingNotifier(),
    );
    expect(ok, isFalse);
  });
}
