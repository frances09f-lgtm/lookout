/// Deterministic goal parser (spec V1: convert the user's input into a
/// structured Agent object; unrestricted NL automation is V3).
///
/// Keyword rules only - no model calls, no pretending. Value watches can
/// fetch a number from a web page; only unrestricted page-change monitoring
/// stays flagged as a later version.
library;

import 'agent.dart';

enum ParseOutcome { ok, needsV2, unclear }

class ParsedGoal {
  final ParseOutcome outcome;
  final String title;
  final AgentType? type;
  final WatchCondition? condition;
  final double? target;

  /// Page to fetch the watched value from, when the goal contains a link.
  final String? sourceUrl;
  final String? note;

  const ParsedGoal._(
      this.outcome, this.title, this.type, this.condition, this.target,
      {this.sourceUrl, this.note});

  factory ParsedGoal.ok({
    required String title,
    required AgentType type,
    required WatchCondition condition,
    required double target,
    String? sourceUrl,
  }) =>
      ParsedGoal._(ParseOutcome.ok, title, type, condition, target,
          sourceUrl: sourceUrl);

  factory ParsedGoal.needsV2(String title) => ParsedGoal._(
      ParseOutcome.needsV2,
      title,
      null,
      null,
      null,
      note: 'This needs full page-change monitoring, which arrives in a '
          'later version. Watching a price or number on a page works now - '
          'include the page link in the goal.');

  factory ParsedGoal.unclear() => const ParsedGoal._(
      ParseOutcome.unclear,
      '',
      null,
      null,
      null,
      note: 'Try one of the suggestion styles below.');
}

class GoalParser {
  static final _money = RegExp(r'(?:₹|\$|rs\.?|inr)?\s*([0-9][0-9,]*(?:\.\d+)?)',
      caseSensitive: false);
  static final _duration = RegExp(
      r'\bin\s+(\d+)\s*(minute|minutes|min|hour|hours|hr|hrs|day|days)\b',
      caseSensitive: false);

  /// A number glued to a comparison phrase ("below 200", "under ₹500",
  /// "less than 10"). This is the threshold the user actually means - never
  /// a digit that merely appears in the watched thing's name
  /// ("Drishyam 3", "iPhone 16").
  static final _conditionNumber = RegExp(
      r'\b(?:below|above|under|over|less than|more than|cheaper than|'
      r'costlier than|drops?\s+(?:to|below)|falls?\s+(?:to|below)|'
      r'go(?:es)?\s+(?:below|above|under|over)|rises?\s+(?:above|over)|'
      r'crosses?|reaches?)\s*(?:₹|\$|rs\.?|inr|usd)?\s*([0-9][0-9,]*(?:\.\d+)?)',
      caseSensitive: false);

  static final _url = RegExp(
      r'(https?://[^\s<>"]+|(?:[a-z0-9][a-z0-9-]*\.)+[a-z]{2,}(?:/[^\s<>"]*)?)',
      caseSensitive: false);

  static const _webWords = [
    'webpage', 'web page', 'website', 'page changes',
    'page change', 'site changes', 'monitor this page', 'watch this page',
  ];
  static const _priceWords = [
    'cheaper', 'price', 'drops below', 'falls below', 'less than', 'under ₹',
    'under rs', 'goes above', 'rises above', 'more than', 'below ₹',
    'below rs', 'above ₹', 'above rs', 'ticket',
  ];
  static const _remindWords = ['remind', 'reminder', "hasn't been completed"];

  static ParseOutcome parseOutcome(String input) =>
      parse(input).outcome;

  /// Extracts the first usable page link from free text, normalised to an
  /// absolute https URL. Returns null when there is no link.
  static String? extractUrl(String text) {
    final m = _url.firstMatch(text);
    if (m == null) return null;
    var u = m.group(1)!;
    u = u.replaceAll(RegExp(r'[.,;:!?\)\]]+$'), '');
    if (!u.toLowerCase().startsWith('http')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) {
      return null;
    }
    return u;
  }

  static ParsedGoal parse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return ParsedGoal.unclear();
    final lower = input.toLowerCase();

    // 1. Price/value watch (a page link turns it into an auto-fetching watch).
    if (_priceWords.any(lower.contains)) {
      final cleaned = lower.replaceAll(',', '');
      final cm = _conditionNumber.firstMatch(cleaned);
      final numText = cm?.group(1) ?? _money.firstMatch(cleaned)?.group(1);
      if (numText == null) return ParsedGoal.unclear();
      final target = double.tryParse(numText);
      if (target == null) return ParsedGoal.unclear();
      final above = lower.contains('goes above') ||
          lower.contains('rises above') ||
          lower.contains('more than') ||
          lower.contains('costlier than') ||
          lower.contains('above ₹') ||
          lower.contains('above rs');
      return ParsedGoal.ok(
        title: _title(input),
        type: AgentType.valueWatch,
        condition: above ? WatchCondition.greaterThan : WatchCondition.lessThan,
        target: target,
        sourceUrl: extractUrl(input),
      );
    }

    // 2. Unrestricted page monitoring: honest later-version marker.
    if (_webWords.any(lower.contains)) return ParsedGoal.needsV2(_title(input));

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
