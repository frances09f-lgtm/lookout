/// Structured Agent object (spec V1 section 2).
///
/// An Agent is a persistent background watch: it is checked on a schedule,
/// evaluates a condition against real data, and notifies the user when the
/// condition is met. No fake functionality: V1 ships two check types that
/// work fully offline (reminder + manual value watch). Webpage monitoring is
/// V2 per the spec.
library;

enum AgentType {
  /// Fires once when a point in time is reached.
  reminder,

  /// Watches a value the user maintains (e.g. a price they see) and fires
  /// when it crosses the target. V1 has no web fetching - the user updates
  /// the current value from the details screen and Lookout evaluates the
  /// condition on every check.
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
  final bool notificationEnabled;

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
    this.notificationEnabled = true,
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
    bool? notificationEnabled,
    bool clearCurrentValue = false,
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
      currentValue: clearCurrentValue ? null : (currentValue ?? this.currentValue),
      previousValue: previousValue ?? this.previousValue,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
    );
  }

  String get typeLabel => switch (type) {
        AgentType.reminder => 'Reminder',
        AgentType.valueWatch => 'Value watch',
      };

  String get statusLabel => switch (status) {
        AgentStatus.active => 'Active',
        AgentStatus.paused => 'Paused',
        AgentStatus.completed => 'Completed',
        AgentStatus.failed => 'Failed',
      };

  /// Human description of the condition shown on cards and details.
  String get conditionLabel => switch (condition) {
        WatchCondition.remindAt =>
          'Remind at ${_fmtTime(DateTime.fromMillisecondsSinceEpoch(target.round()))}',
        WatchCondition.lessThan => 'Notify when value drops below ${_fmtNum(target)}',
        WatchCondition.greaterThan => 'Notify when value rises above ${_fmtNum(target)}',
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
        'notificationEnabled': notificationEnabled ? 1 : 0,
      };

  factory Agent.fromMap(Map<String, Object?> m) => Agent(
        id: m['id'] as int?,
        title: m['title'] as String,
        originalPrompt: m['originalPrompt'] as String,
        type: AgentType.values.byName(m['type'] as String),
        status: AgentStatus.values.byName(m['status'] as String),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int),
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
        notificationEnabled: (m['notificationEnabled'] as int) == 1,
      );
}
