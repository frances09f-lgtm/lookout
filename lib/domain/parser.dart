/// Deterministic goal parser (spec V1: convert the user's input into a
/// structured Agent object; unrestricted NL automation is V3).
///
/// Keyword rules only - no model calls, no pretending. Anything that needs
/// web monitoring is explicitly flagged as V2 functionality.
library;

import 'agent.dart';

enum ParseOutcome { ok, needsV2, unclear }

class ParsedGoal {
  final ParseOutcome outcome;
  final String title;
  final AgentType? type;
  final WatchCondition? condition;
  final double? target;
  final String? note;

  const ParsedGoal._(
      this.outcome, this.title, this.type, this.condition, this.target,
      [this.note]);

  factory ParsedGoal.ok(
          {required String title,
          required AgentType type,
          required WatchCondition condition,
          required double target}) =>
      ParsedGoal._(ParseOutcome.ok, title, type, condition, target);

  factory ParsedGoal.needsV2(String title) => ParsedGoal._(
      ParseOutcome.needsV2,
      title,
      null,
      null,
      null,
      'This needs webpage monitoring, which arrives in V2.');

  factory ParsedGoal.unclear() => const ParsedGoal._(
      ParseOutcome.unclear,
      '',
      null,
      null,
      null,
      'Try one of the suggestion styles below.');
}

class GoalParser {
  static final _money = RegExp(r'(?:₹|\$|rs\.?|inr)?\s*([0-9][0-9,]*(?:\.\d+)?)',
      caseSensitive: false);
  static final _duration = RegExp(
      r'\bin\s+(\d+)\s*(minute|minutes|min|hour|hours|hr|hrs|day|days)\b',
      caseSensitive: false);

  static const _webWords = [
    'webpage', 'web page', 'website', 'http', 'url', 'page changes',
    'page change', 'site changes', 'monitor this page', 'watch this page',
  ];
  static const _priceWords = [
    'cheaper', 'price', 'drops below', 'falls below', 'less than', 'under ₹',
    'under rs', 'goes above', 'rises above', 'more than',
  ];
  static const _remindWords = ['remind', 'reminder', "hasn't been completed"];

  static ParseOutcome parseOutcome(String input) =>
      parse(input).outcome;

  static ParsedGoal parse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return ParsedGoal.unclear();
    final lower = input.toLowerCase();

    // 1. Web monitoring: honest V2 marker, no pretend button.
    if (_webWords.any(lower.contains)) return ParsedGoal.needsV2(_title(input));

    // 2. Price/value watch.
    if (_priceWords.any(lower.contains)) {
      final m = _money.firstMatch(lower.replaceAll(',', ''));
      if (m == null) return ParsedGoal.unclear();
      final target = double.tryParse(m.group(1) ?? '');
      if (target == null) return ParsedGoal.unclear();
      final above = lower.contains('goes above') ||
          lower.contains('rises above') ||
          lower.contains('more than');
      return ParsedGoal.ok(
        title: _title(input),
        type: AgentType.valueWatch,
        condition: above ? WatchCondition.greaterThan : WatchCondition.lessThan,
        target: target,
      );
    }

    // 3. Reminder.
    if (_remindWords.any(lower.contains)) {
      var minutes = 60; // default: remind in 1 hour
      final d = _duration.firstMatch(lower);
      if (d != null) {
        final n = int.tryParse(d.group(1) ?? '') ?? 60;
        final unit = d.group(2)!.toLowerCase();
        minutes = unit.startsWith('min')
            ? n
            : unit.startsWith('h')
                ? n * 60
                : n * 60 * 24;
      }
      final due = DateTime.now().add(Duration(minutes: minutes));
      return ParsedGoal.ok(
        title: _title(input),
        type: AgentType.reminder,
        condition: WatchCondition.remindAt,
        target: due.millisecondsSinceEpoch.toDouble(),
      );
    }

    return ParsedGoal.unclear();
  }

  static String _title(String input) =>
      input.length <= 60 ? input : '${input.substring(0, 57)}...';
}
