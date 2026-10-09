import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/presentation/home_screen.dart';

void main() {
  final now = DateTime(2026, 10, 9, 10);
  Agent make({double? current, DateTime? read}) => Agent(
    title: 'No source',
    originalPrompt: 'watch product',
    type: AgentType.valueWatch,
    status: AgentStatus.active,
    createdAt: now.subtract(const Duration(days: 1)),
    checkInterval: const Duration(minutes: 15),
    condition: WatchCondition.lessThan,
    target: 10,
    currentValue: current,
    lastSuccessfulReadAt: read,
    lastSuccessfulValue: current,
    nextCheckAt: now.subtract(const Duration(hours: 2)),
  );
  test(
    'due recovery records failed/no-source attempt, never fabricates a value',
    () async {
      final repo = InMemoryAgentRepository();
      final id = await repo.insertAgent(make());
      final checker = AgentChecker(
        repo: repo,
        notifier: RecordingNotifier(),
        clock: () => now,
      );
      expect(await checker.checkDueAgents(), 1);
      final updated = await repo.agentById(id);
      expect(updated!.lastCheckedAt, now);
      expect(updated.currentValue, isNull);
      expect(updated.status, AgentStatus.active);
      expect(await checker.checkDueAgents(), 0);
    },
  );
  test('manual, recent read and stale read never called live', () {
    expect(valueProvenance(make(current: 12), now), contains('Saved/manual'));
    expect(
      valueProvenance(
        make(current: 12, read: now.subtract(const Duration(days: 1))),
        now,
      ),
      contains('Stale saved'),
    );
    expect(
      valueProvenance(
        make(current: 12, read: now.subtract(const Duration(minutes: 1))),
        now,
      ),
      contains('Recent successful'),
    );
  });
}
