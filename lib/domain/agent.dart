/// Structured Agent object (spec V1 section 2).
///
/// An Agent is a persistent background watch: it is checked on a schedule,
/// evaluates a condition against real data, and notifies the user when the
/// condition is met. No fake functionality: V1 ships two check types that
/// work fully offline (reminder + manual value watch). Webpage monitoring is
/// V2 per the spec.
library;

import 'dart:convert';

import 'ticket_task.dart';

enum AgentType {
  /// Fires once when a point in time is reached.
  reminder,

  /// Watches a numeric value (e.g. a price) and fires when it crosses the
  /// target. When the agent has a sourceUrl, Lookout fetches the page and
  /// reads the value itself on every check; without one, the user updates
  /// the value from the details screen.
  valueWatch,
}

enum AgentStatus { active, paused, completed, failed }

enum WatchCondition {
  /// reminder: fire when now >= targetTimeMillis.
  remindAt,

  /// valueWatch: fire when currentValue < target.
  lessThan,

  /// valueWatch: fire when currentValue > target.
  greaterThan,
}

class Agent {
  final int? id;
  final String title;
  final String originalPrompt;
  final AgentType type;
  final AgentStatus status;
  final DateTime createdAt;
  final DateTime? lastCheckedAt;
  final DateTime? nextCheckAt;
  final Duration checkInterval;
  final WatchCondition condition;

  /// reminder: epoch millis of the due time. valueWatch: numeric threshold.
  final double target;
  final double? currentValue;
  final double? previousValue;

  /// Page to fetch the watched value from. Null = manual value watch.
  final String? sourceUrl;

  /// Reviewed product identity for strict automatic price checks (JSON).
  final String? sourceIdentity;
  final bool notificationEnabled;
  final DateTime? lastSuccessfulReadAt;
  final double? lastSuccessfulValue;
  final String? lastReadMethod;
  final String? lastReadSourceUrl;

  const Agent({
    this.id,
    required this.title,
    required this.originalPrompt,
    required this.type,
    required this.status,
    required this.createdAt,
    this.lastCheckedAt,
    this.nextCheckAt,
    required this.checkInterval,
    required this.condition,
    required this.target,
    this.currentValue,
    this.previousValue,
    this.sourceUrl,
    this.sourceIdentity,
    this.notificationEnabled = true,
    this.lastSuccessfulReadAt,
    this.lastSuccessfulValue,
    this.lastReadMethod,
    this.lastReadSourceUrl,
  });

  Agent copyWith({
    int? id,
    String? title,
    AgentStatus? status,
    DateTime? lastCheckedAt,
    DateTime? nextCheckAt,
    Duration? checkInterval,
    double? target,
    double? currentValue,
    double? previousValue,
    String? sourceUrl,
    String? sourceIdentity,
    bool clearSourceIdentity = false,
    bool? notificationEnabled,
    DateTime? lastSuccessfulReadAt,
    double? lastSuccessfulValue,
    String? lastReadMethod,
    String? lastReadSourceUrl,
    bool clearCurrentValue = false,
    bool clearSourceUrl = false,
  }) {
    return Agent(
      id: id ?? this.id,
      title: title ?? this.title,
      originalPrompt: originalPrompt,
      type: type,
      status: status ?? this.status,
      createdAt: createdAt,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      nextCheckAt: nextCheckAt ?? this.nextCheckAt,
      checkInterval: checkInterval ?? this.checkInterval,
      condition: condition,
      target: target ?? this.target,
      currentValue: clearCurrentValue
          ? null
          : (currentValue ?? this.currentValue),
      previousValue: previousValue ?? this.previousValue,
      sourceUrl: clearSourceUrl ? null : (sourceUrl ?? this.sourceUrl),
      sourceIdentity: clearSourceIdentity || clearSourceUrl
          ? null
          : sourceIdentity ?? this.sourceIdentity,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      lastSuccessfulReadAt: lastSuccessfulReadAt ?? this.lastSuccessfulReadAt,
      lastSuccessfulValue: lastSuccessfulValue ?? this.lastSuccessfulValue,
      lastReadMethod: lastReadMethod ?? this.lastReadMethod,
      lastReadSourceUrl: lastReadSourceUrl ?? this.lastReadSourceUrl,
    );
  }

  bool get isTextWatch {
    try {
      return sourceIdentity != null &&
          (jsonDecode(sourceIdentity!) as Map)['kind'] == 'textPresence';
    } catch (_) {
      return false;
    }
  }

  String readingLabel(double? value) => isTextWatch
      ? value == null
            ? 'Not checked'
            : value == 1
            ? 'Phrase present'
            : 'Phrase absent on this page'
      : value?.toString() ?? 'Not set';
  String? get watchedPhrase {
    try {
      return isTextWatch
          ? (jsonDecode(sourceIdentity!) as Map)['phrase'] as String?
          : null;
    } catch (_) {
      return null;
    }
  }

  bool get isUnsupportedTicketWatch =>
      type == AgentType.valueWatch &&
      !isTextWatch &&
      TicketTaskPolicy.isPriceTask(originalPrompt);

  String get typeLabel => switch (type) {
    AgentType.reminder => 'Reminder',
    AgentType.valueWatch =>
      isUnsupportedTicketWatch
          ? 'Ticket price watch'
          : isTextWatch
          ? 'Page text watch'
          : 'Value watch',
  };

  /// Derived from existing persisted fields, so legacy source-less tasks also
  /// enter resolution without deleting, renumbering or migrating their history.
  bool get needsSourceResolution =>
      type == AgentType.valueWatch &&
      (isUnsupportedTicketWatch ||
          ((sourceUrl == null || sourceUrl!.trim().isEmpty) &&
              (currentValue == null || isTextWatch)));

  String get statusLabel =>
      status == AgentStatus.active && isUnsupportedTicketWatch
      ? 'Ticket monitoring unavailable'
      : status == AgentStatus.active && needsSourceResolution
      ? 'Needs source'
      : switch (status) {
          AgentStatus.active => 'Active',
          AgentStatus.paused => 'Paused',
          AgentStatus.completed => 'Completed',
          AgentStatus.failed => 'Failed',
        };

  /// Human description of the condition shown on cards and details.
  String get conditionLabel => isTextWatch
      ? 'Notify when this page contains “$watchedPhrase”'
      : switch (condition) {
          WatchCondition.remindAt =>
            'Remind at ${_fmtTime(DateTime.fromMillisecondsSinceEpoch(target.round()))}',
          WatchCondition.lessThan =>
            'Notify when value drops below ${_fmtNum(target)}',
          WatchCondition.greaterThan =>
            'Notify when value rises above ${_fmtNum(target)}',
        };

  static String _fmtTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.day}/${t.month} $h:$m';
  }

  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'originalPrompt': originalPrompt,
    'type': type.name,
    'status': status.name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'lastCheckedAt': lastCheckedAt?.millisecondsSinceEpoch,
    'nextCheckAt': nextCheckAt?.millisecondsSinceEpoch,
    'checkIntervalMinutes': checkInterval.inMinutes,
    'condition': condition.name,
    'target': target,
    'currentValue': currentValue,
    'previousValue': previousValue,
    'sourceUrl': sourceUrl,
    'sourceIdentity': sourceIdentity,
    'notificationEnabled': notificationEnabled ? 1 : 0,
    'lastSuccessfulReadAt': lastSuccessfulReadAt?.millisecondsSinceEpoch,
    'lastSuccessfulValue': lastSuccessfulValue,
    'lastReadMethod': lastReadMethod,
    'lastReadSourceUrl': lastReadSourceUrl,
  };

  factory Agent.fromMap(Map<String, Object?> m) => Agent(
    id: m['id'] as int?,
    title: m['title'] as String,
    originalPrompt: m['originalPrompt'] as String,
    type: AgentType.values.byName(m['type'] as String),
    status: AgentStatus.values.byName(m['status'] as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
    lastCheckedAt: m['lastCheckedAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['lastCheckedAt'] as int),
    nextCheckAt: m['nextCheckAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['nextCheckAt'] as int),
    checkInterval: Duration(minutes: m['checkIntervalMinutes'] as int),
    condition: WatchCondition.values.byName(m['condition'] as String),
    target: (m['target'] as num).toDouble(),
    currentValue: (m['currentValue'] as num?)?.toDouble(),
    previousValue: (m['previousValue'] as num?)?.toDouble(),
    sourceUrl: m['sourceUrl'] as String?,
    sourceIdentity: m['sourceIdentity'] as String?,
    notificationEnabled: (m['notificationEnabled'] as int) == 1,
    lastSuccessfulReadAt: m['lastSuccessfulReadAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['lastSuccessfulReadAt'] as int),
    lastSuccessfulValue: (m['lastSuccessfulValue'] as num?)?.toDouble(),
    lastReadMethod: m['lastReadMethod'] as String?,
    lastReadSourceUrl: m['lastReadSourceUrl'] as String?,
  );
}
