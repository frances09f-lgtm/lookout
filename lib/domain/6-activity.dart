/// One entry in an agent's activity log (spec V1 section 4).
class ActivityEntry {
  final int? id;
  final int agentId;
  final DateTime timestamp;
  final String message;

  const ActivityEntry({
    this.id,
    required this.agentId,
    required this.timestamp,
    required this.message,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'agentId': agentId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'message': message,
      };

  factory ActivityEntry.fromMap(Map<String, Object?> m) => ActivityEntry(
        id: m['id'] as int?,
        agentId: m['agentId'] as int,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
        message: m['message'] as String,
      );

  /// Tolerant decode: SQLite's dynamic typing lets an INTEGER column hold
  /// TEXT, and one unreadable row must not blank a task's whole history
  /// behind "Could not load". Returns null only when a row cannot be read
  /// at all; callers drop nulls.
  static ActivityEntry? tryFromMap(Map<String, Object?> m) {
    int? asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    final agentId = asInt(m['agentId']);
    final ts = asInt(m['timestamp']);
    final message = m['message'];
    if (agentId == null || ts == null || message == null) return null;
    return ActivityEntry(
      id: asInt(m['id']),
      agentId: agentId,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      message: message.toString(),
    );
  }
}
