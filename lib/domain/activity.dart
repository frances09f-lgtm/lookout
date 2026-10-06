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
}
