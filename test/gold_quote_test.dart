import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/services/gold_quote.dart';
import 'package:lookout/services/checker.dart';
import 'package:lookout/services/page_fetch.dart';
import 'package:lookout/services/notifications.dart';
import 'package:lookout/data/agent_repository.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/domain/parser.dart';

void main() {
  final now = DateTime(2026, 10, 8, 12);
  String data(int age, double bid, double ask) => jsonEncode([
    {
      'ts': now.millisecondsSinceEpoch - age,
      'spreadProfilePrices': [
        {'bid': bid, 'ask': ask},
      ],
    },
  ]);
  test('exact device threshold and named digits', () {
    for (final prompt in [
      'tell me when iphone goes cheaper than 54000',
      'iPhone 16 cheaper than ₹54,000',
    ]) {
      expect(GoalParser.parse(prompt).target, 54000);
    }
  });
  test('gold fresh mid rejects stale crossed malformed', () {
    expect(GoldQuote.parse(data(1000, 4120, 4121), now: now).value, 4120.5);
    expect(GoldQuote.parse(data(300001, 4120, 4121), now: now).ok, false);
    expect(GoldQuote.parse(data(0, 4122, 4121), now: now).ok, false);
    expect(GoldQuote.parse('broken', now: now).ok, false);
  });
  test('gold not gold jewelry or phone', () {
    expect(GoldQuote.isGold('watch the gold price below 4126'), true);
    expect(GoldQuote.isGold('gold ring price below 2000'), false);
    expect(GoldQuote.isGold('iphone gold price below 54000'), false);
  });
  test(
    'gold source free and failure stays active no stale comparison',
    () async {
      final repo = InMemoryAgentRepository();
      final n = RecordingNotifier();
      final id = await repo.insertAgent(
        Agent(
          title: 'gold',
          originalPrompt: 'watch the gold price below 4126',
          type: AgentType.valueWatch,
          status: AgentStatus.active,
          createdAt: now,
          checkInterval: const Duration(minutes: 30),
          condition: WatchCondition.lessThan,
          target: 4126,
          currentValue: 1,
          sourceUrl: 'https://www.tradingview.com',
        ),
      );
      final c = AgentChecker(
        repo: repo,
        notifier: n,
        clock: () => now,
        fetcher: (_) => throw StateError('should not read page'),
        goldFetcher: () async => FetchOutcome.failed('Swissquote HTTP 403'),
      );
      await c.checkDueAgents();
      expect(n.shown, isEmpty);
      expect((await repo.agentById(id))!.status, AgentStatus.active);
      expect(
        (await repo.activityFor(id))
            .any((x) => x.message.contains('no fresh value')),
        true,
      );
      final c2 = AgentChecker(
        repo: repo,
        notifier: n,
        clock: () => now,
        goldFetcher: () async =>
            GoldQuote.parse(data(1000, 4120, 4121), now: now),
      );
      await c2.checkAgent((await repo.agentById(id))!);
      expect(n.shown.length, 1);
      expect((await repo.agentById(id))!.lastReadSourceUrl, GoldQuote.url);
    },
  );
}
