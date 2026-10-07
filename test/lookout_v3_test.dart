import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/domain/parser.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/services/page_fetch.dart';

void main() {
  group('GoalParser condition-anchored number', () {
    test('Drishyam 3 case: threshold comes from "below 200", not the title', () {
      final p = GoalParser.parse(
          'Ticket Price at Fortune cineplex ichalkaranji of Drishyam 3 Movie, tell me when the price go below 200');
      expect(p.outcome, ParseOutcome.ok);
      expect(p.type, AgentType.valueWatch);
      expect(p.condition, WatchCondition.lessThan);
      expect(p.target, 200);
    });
    test('iPhone 16 case: name digit is not the threshold', () {
      final p = GoalParser.parse(
          'Tell me when iPhone 16 becomes cheaper than ₹50,000');
      expect(p.target, 50000);
    });
    test('above phrasing keeps greaterThan', () {
      final p = GoalParser.parse('Alert when gold goes above ₹7,500');
      expect(p.condition, WatchCondition.greaterThan);
      expect(p.target, 7500);
    });
  });

  group('GoalParser.extractUrl', () {
    test('finds and normalises a bare domain', () {
      expect(GoalParser.extractUrl('watch bookmyshow.com/ticket below 200'),
          'https://bookmyshow.com/ticket');
    });
    test('keeps a full URL and strips trailing punctuation', () {
      expect(GoalParser.extractUrl('check https://x.com/p, below 200'),
          'https://x.com/p');
    });
    test('returns null when there is no link', () {
      expect(GoalParser.extractUrl('ticket price at fortune cineplex below 200'),
          isNull);
    });
    test('parse attaches the url to the watch', () {
      final p = GoalParser.parse(
          'Tell me when https://shop.example.com/item is below ₹500');
      expect(p.sourceUrl, 'https://shop.example.com/item');
      expect(p.target, 500);
    });
  });

  group('Agent sourceUrl persistence', () {
    test('map round-trip keeps the source url', () {
      final a = Agent(
        id: 1,
        title: 't',
        originalPrompt: 'p',
        type: AgentType.valueWatch,
        status: AgentStatus.active,
        createdAt: DateTime(2026, 1, 1),
        checkInterval: const Duration(minutes: 30),
        condition: WatchCondition.lessThan,
        target: 200,
        sourceUrl: 'https://x.com',
      );
      final b = Agent.fromMap(a.toMap());
      expect(b.sourceUrl, 'https://x.com');
    });
    test('old rows without the column map to null', () {
      final a = Agent(
        id: 1,
        title: 't',
        originalPrompt: 'p',
        type: AgentType.valueWatch,
        status: AgentStatus.active,
        createdAt: DateTime(2026, 1, 1),
        checkInterval: const Duration(minutes: 30),
        condition: WatchCondition.lessThan,
        target: 200,
      );
      final m = a.toMap()..remove('sourceUrl');
      expect(Agent.fromMap(m).sourceUrl, isNull);
    });
  });

  group('AgentChecker web fetching', () {
    Agent watch({String? url, double? current}) => Agent(
          title: 'ticket',
          originalPrompt: 'p',
          type: AgentType.valueWatch,
          status: AgentStatus.active,
          createdAt: DateTime(2026, 1, 1),
          nextCheckAt: DateTime(2026, 1, 1),
          checkInterval: const Duration(minutes: 30),
          condition: WatchCondition.lessThan,
          target: 200,
          currentValue: current,
          sourceUrl: url,
        );

    Future<(CheckResult, Agent)> run(InMemoryAgentRepository repo,
        Agent w, Future<FetchOutcome> Function(String)? fetcher) async {
      final id = await repo.insertAgent(w);
      final stored = (await repo.agentById(id))!;
      final checker = AgentChecker(
          repo: repo,
          notifier: RecordingNotifier(),
          clock: () => DateTime(2026, 1, 1, 12),
          fetcher: fetcher);
      final r = await checker.checkAgent(stored);
      return (r, (await repo.agentById(id))!);
    }

    test('fetched value below target triggers and stores the value', () async {
      final repo = InMemoryAgentRepository();
      final (r, saved) = await run(repo, watch(url: 'https://x.com'),
          (url) async => FetchOutcome.found(180, 'Found 180.0 on x.com'));
      expect(r.conditionMet, isTrue);
      expect(saved.currentValue, 180);
      expect(saved.status, AgentStatus.completed);
    });

    test('fetched value above target does not trigger', () async {
      final repo = InMemoryAgentRepository();
      final (r, saved) = await run(repo, watch(url: 'https://x.com'),
          (url) async => FetchOutcome.found(250, 'Found 250.0 on x.com'));
      expect(r.conditionMet, isFalse);
      expect(saved.currentValue, 250);
      expect(saved.previousValue, isNull);
    });

    test('fetch failure is honest: keeps last value, no evaluation', () async {
      final repo = InMemoryAgentRepository();
      final (r, saved) = await run(repo, watch(url: 'https://x.com', current: 150),
          (url) async =>
              FetchOutcome.failed('Could not fetch page (HTTP 404) from x.com'));
      expect(r.conditionMet, isFalse);
      expect(r.summary, contains('HTTP 404'));
      expect(saved.currentValue, 150);
      expect(saved.status, AgentStatus.active);
    });

    test('movement between fetches records previousValue', () async {
      final repo = InMemoryAgentRepository();
      final (r, saved) = await run(repo, watch(url: 'https://x.com', current: 250),
          (url) async => FetchOutcome.found(240, 'Found 240.0 on x.com'));
      expect(r.conditionMet, isFalse);
      expect(saved.currentValue, 240);
      expect(saved.previousValue, 250);
    });

    test('watch without a source page still works manually', () async {
      final repo = InMemoryAgentRepository();
      final (r, _) = await run(repo, watch(current: 100), null);
      expect(r.conditionMet, isTrue);
    });
  });
}
