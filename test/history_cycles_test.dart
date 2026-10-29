import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/activity.dart';
import 'package:lookout/presentation/history_cycles.dart';

ActivityEntry mk(String message, DateTime at) =>
    ActivityEntry(agentId: 1, message: message, timestamp: at);

void main() {
  group('creation entry', () {
    test('a lone Task created entry renders as creation, not an edit', () {
      final at = DateTime.now().subtract(const Duration(minutes: 3));
      final cycles = groupHistoryCycles([mk('Task created', at)]);
      expect(cycles, hasLength(1));
      expect(cycles.single.title, 'Task created');
      expect(cycles.single.badge, 'Created');
      expect(cycles.single.steps, isEmpty);
      expect(cycles.single.looksInterrupted, isFalse);
    });
  });

  group('edit/save groups', () {
    final at = DateTime.now().subtract(const Duration(hours: 9));

    test('a target-edit group is not rendered as a failed check', () {
      final cycles = groupHistoryCycles([mk('Target changed to 80260.0', at)]);
      expect(cycles, hasLength(1));
      expect(cycles.single.state, CycleState.updated);
      expect(cycles.single.title, 'Task updated');
      expect(cycles.single.badge, 'Saved');
      expect(cycles.single.looksInterrupted, isFalse);
    });

    test('multiple edits at the same instant group together', () {
      final cycles = groupHistoryCycles([
        mk('Target changed to 1', at),
        mk('Interval changed to 15 minutes', at),
      ]);
      expect(cycles, hasLength(1));
      expect(cycles.single.state, CycleState.updated);
    });
  });

  group('interrupted checks', () {
    test('started but no outcome, old: looks interrupted', () {
      final at = DateTime.now().subtract(const Duration(minutes: 5));
      final cycles = groupHistoryCycles([mk('Started check', at)]);
      expect(cycles.single.state, CycleState.noResult);
      expect(cycles.single.looksInterrupted, isTrue);
    });

    test('recent started-only group is still running, not flagged', () {
      final at = DateTime.now().subtract(const Duration(seconds: 30));
      final cycles = groupHistoryCycles([mk('Started check', at)]);
      expect(cycles.single.looksInterrupted, isFalse);
    });

    test('finished cycle is never flagged', () {
      final at = DateTime.now().subtract(const Duration(hours: 1));
      final cycles = groupHistoryCycles([
        mk('Started check', at),
        mk('Fetched data: 80260.0', at),
        mk('Condition not met', at),
      ]);
      expect(cycles.single.state, CycleState.notMet);
      expect(cycles.single.looksInterrupted, isFalse);
    });
  });

  group('kv store', () {
    test('in-memory roundtrip', () async {
      final repo = InMemoryAgentRepository();
      expect(await repo.getKv('k'), isNull);
      await repo.putKv('k', 'v1');
      expect(await repo.getKv('k'), 'v1');
      await repo.putKv('k', 'v2');
      expect(await repo.getKv('k'), 'v2');
    });
  });
}
