import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/domain/agent.dart';
import 'package:lookout/domain/parser.dart';

void main() {
  test('price target parses to value watch below', () {
    final p = GoalParser.parse('Tell me when this product becomes cheaper than ₹50,000');
    expect(p.outcome, ParseOutcome.ok);
    expect(p.type, AgentType.valueWatch);
    expect(p.condition, WatchCondition.lessThan);
    expect(p.target, 50000);
  });

  test('above target parses to greaterThan', () {
    final p = GoalParser.parse('Alert me when the price goes above 2100');
    expect(p.outcome, ParseOutcome.ok);
    expect(p.condition, WatchCondition.greaterThan);
    expect(p.target, 2100);
  });

  test('reminder with duration parses due time ~2h out', () {
    final before = DateTime.now();
    final p = GoalParser.parse("Remind me in 2 hours if this task hasn't been completed");
    final after = DateTime.now();
    expect(p.outcome, ParseOutcome.ok);
    expect(p.type, AgentType.reminder);
    final due = DateTime.fromMillisecondsSinceEpoch(p.target!.round());
    expect(due.isAfter(before.add(const Duration(hours: 1, minutes: 59))), isTrue);
    expect(due.isBefore(after.add(const Duration(hours: 2, minutes: 1))), isTrue);
  });

  test('reminder without duration defaults to 1 hour', () {
    final p = GoalParser.parse('Remind me about the dentist');
    expect(p.outcome, ParseOutcome.ok);
    expect(p.type, AgentType.reminder);
  });

  test('webpage requests are honestly marked as V2, never faked', () {
    final p = GoalParser.parse('Tell me when this webpage changes');
    expect(p.outcome, ParseOutcome.needsV2);
  });

  test('gibberish is unclear', () {
    expect(GoalParser.parse('asdf qwer').outcome, ParseOutcome.unclear);
  });
}
