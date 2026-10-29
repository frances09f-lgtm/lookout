import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/page_fetch.dart';

Agent goldWatch({int? id}) => Agent(
      id: id,
      title: 'gold',
      originalPrompt: 'Tell me when Gold Price rises above 4030',
      type: AgentType.valueWatch,
      status: AgentStatus.active,
      createdAt: DateTime(2026, 10, 29),
      checkInterval: const Duration(minutes: 15),
      condition: WatchCondition.greaterThan,
      target: 4030,
      currentValue: 4022.28,
      sourceUrl: 'https://in.investing.com/currencies/xau-usd',
      nextCheckAt: DateTime(2026, 10, 29, 14, 0),
    );

class ScriptedChecker {
  static AgentChecker withOutcomes(
    InMemoryAgentRepository repo,
    List<FetchOutcome> outcomes,
  ) {
    var i = 0;
    return AgentChecker(
      repo: repo,
      notifier: RecordingNotifier(),
      clock: () => DateTime(2026, 10, 29, 14, 5),
      fetcher: (_) async => outcomes[i < outcomes.length ? i++ : i - 1],
    );
  }
}

void main() {
  test('three consecutive hard blocks pause automatic checks', () async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(goldWatch());
    final blocked = FetchOutcome.failed(
      'Could not fetch page (HTTP 403) from in.investing.com',
    );
    final checker = ScriptedChecker.withOutcomes(repo, [blocked]);

    await checker.checkAgent((await repo.agentById(id))!);
    await checker.checkAgent((await repo.agentById(id))!);
    var a = (await repo.agentById(id))!;
    expect(a.sourceBlocked, isFalse);
    expect(a.consecutiveSourceBlocks, 2);

    await checker.checkAgent(a);
    a = (await repo.agentById(id))!;
    expect(a.sourceBlocked, isTrue);

    // The paused watch is never due, and history says so plainly.
    final due = await repo.dueAgents(DateTime(2026, 10, 29, 15, 0));
    expect(due, isEmpty);
    final log = await repo.activityFor(id);
    expect(
      log.map((e) => e.message),
      contains(contains('Automatic checks paused')),
    );
  });

  test('a successful read clears the block count', () async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(goldWatch());
    final blocked = FetchOutcome.failed(
      'Could not fetch page (HTTP 403) from in.investing.com',
    );
    var checker = ScriptedChecker.withOutcomes(repo, [blocked, blocked]);
    await checker.checkAgent((await repo.agentById(id))!);
    await checker.checkAgent((await repo.agentById(id))!);
    expect((await repo.agentById(id))!.consecutiveSourceBlocks, 2);

    checker = ScriptedChecker.withOutcomes(
      repo,
      [FetchOutcome.found(4023.5, 'Found 4023.5 on goldpricez.com')],
    );
    await checker.checkAgent((await repo.agentById(id))!);
    final a = (await repo.agentById(id))!;
    expect(a.consecutiveSourceBlocks, 0);
    expect(a.sourceBlocked, isFalse);
    expect(a.currentValue, 4023.5);
  });

  test('transient failures neither increment nor reset the count', () async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(goldWatch());
    final blocked = FetchOutcome.failed(
      'Could not fetch page (HTTP 403) from in.investing.com',
    );
    final timeout = FetchOutcome.failed('Connection timed out');
    final checker = ScriptedChecker.withOutcomes(
      repo,
      [blocked, timeout, timeout],
    );
    await checker.checkAgent((await repo.agentById(id))!);
    await checker.checkAgent((await repo.agentById(id))!);
    await checker.checkAgent((await repo.agentById(id))!);
    final a = (await repo.agentById(id))!;
    expect(a.consecutiveSourceBlocks, 1);
    expect(a.sourceBlocked, isFalse);
    // A transient failure still schedules an honest retry.
    final log = await repo.activityFor(id);
    expect(
      log.map((e) => e.message),
      contains(contains('Read retry scheduled')),
    );
  });

  test('changing the source page resets the count and reschedules', () async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(goldWatch());
    final blocked = FetchOutcome.failed(
      'Could not fetch page (HTTP 403) from in.investing.com',
    );
    final checker = ScriptedChecker.withOutcomes(repo, [blocked]);
    for (var n = 0; n < 3; n++) {
      await checker.checkAgent((await repo.agentById(id))!);
    }
    var a = (await repo.agentById(id))!;
    expect(a.sourceBlocked, isTrue);
    expect(await repo.dueAgents(DateTime(2026, 10, 29, 15, 0)), isEmpty);

    // What "Set source page" now does.
    await repo.updateAgent(
      a.copyWith(
        sourceUrl: 'https://goldpricez.com/us/ounce',
        clearSourceIdentity: true,
        consecutiveSourceBlocks: 0,
        nextCheckAt: DateTime(2026, 10, 29, 14, 5),
      ),
    );
    a = (await repo.agentById(id))!;
    expect(a.sourceBlocked, isFalse);
    expect(
      (await repo.dueAgents(DateTime(2026, 10, 29, 14, 6))).map((x) => x.id),
      contains(id),
    );
  });

  test('an established wall pauses from recorded history, not 3 more polls',
      () async {
    final repo = InMemoryAgentRepository();
    final id = await repo.insertAgent(goldWatch());
    // Pre-upgrade history: the counter is still 0, but the log shows an
    // established wall with one transient blip inside it.
    final t = DateTime(2026, 10, 29, 13, 0);
    for (var n = 0; n < 5; n++) {
      await repo.logActivity(
        id,
        n == 2
            ? 'Unable to check: Connection timed out'
            : 'Unable to check: Could not fetch page (HTTP 403) from in.investing.com',
        t.add(Duration(minutes: 15 * n)),
      );
    }
    final blocked = FetchOutcome.failed(
      'Could not fetch page (HTTP 403) from in.investing.com',
    );
    final checker = ScriptedChecker.withOutcomes(repo, [blocked]);
    await checker.checkAgent((await repo.agentById(id))!);
    final a = (await repo.agentById(id))!;
    // 4 recorded hard blocks (the transient blip neither counts nor breaks) + the fresh one.
    expect(a.consecutiveSourceBlocks, 5);
    expect(a.sourceBlocked, isTrue);
    expect(await repo.dueAgents(DateTime(2026, 10, 29, 15, 0)), isEmpty);
    final log = await repo.activityFor(id);
    expect(
      log.map((e) => e.message),
      contains(contains('Automatic checks paused')),
    );
  });
}
