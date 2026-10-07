/// SQLite-backed repository (spec V1: SQLite/Drift or Isar, local-first).
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/agent.dart';
import '../domain/activity.dart';
import 'agent_repository.dart';

class SqfliteAgentRepository implements AgentRepository {
  static const _dbName = 'lookout.db';
  static const _dbVersion = 3;

  final Database _db;

  SqfliteAgentRepository._(this._db);

  static Future<SqfliteAgentRepository> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), _dbName);
    final db = await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE agents(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            originalPrompt TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            lastCheckedAt INTEGER,
            nextCheckAt INTEGER,
            checkIntervalMinutes INTEGER NOT NULL,
            condition TEXT NOT NULL,
            target REAL NOT NULL,
            currentValue REAL,
            previousValue REAL,
            sourceUrl TEXT,
            lastSuccessfulReadAt INTEGER,
            lastSuccessfulValue REAL,
            lastReadMethod TEXT,
            lastReadSourceUrl TEXT,
            notificationEnabled INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE activity(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            agentId INTEGER NOT NULL,
            timestamp INTEGER NOT NULL,
            message TEXT NOT NULL,
            FOREIGN KEY(agentId) REFERENCES agents(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_activity_agent ON activity(agentId, timestamp)',
        );
        await db.execute(
          'CREATE INDEX idx_agents_due ON agents(status, nextCheckAt)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE agents ADD COLUMN lastSuccessfulReadAt INTEGER',
          );
          await db.execute(
            'ALTER TABLE agents ADD COLUMN lastSuccessfulValue REAL',
          );
          await db.execute('ALTER TABLE agents ADD COLUMN lastReadMethod TEXT');
          await db.execute(
            'ALTER TABLE agents ADD COLUMN lastReadSourceUrl TEXT',
          );
        }
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE agents ADD COLUMN sourceUrl TEXT');
        }
      },
    );
    await db.execute('PRAGMA foreign_keys = ON');
    return SqfliteAgentRepository._(db);
  }

  @override
  Future<List<Agent>> allAgents() async {
    final rows = await _db.query('agents', orderBy: 'createdAt DESC');
    return rows.map(Agent.fromMap).toList();
  }

  @override
  Future<Agent?> agentById(int id) async {
    final rows = await _db.query('agents', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Agent.fromMap(rows.first);
  }

  @override
  Future<int> insertAgent(Agent agent) =>
      _db.insert('agents', agent.toMap()..remove('id'));

  @override
  Future<void> updateAgent(Agent agent) => _db.update(
    'agents',
    agent.toMap()..remove('id'),
    where: 'id = ?',
    whereArgs: [agent.id],
  );

  @override
  Future<void> deleteAgent(int id) =>
      _db.delete('agents', where: 'id = ?', whereArgs: [id]);

  @override
  Future<List<Agent>> dueAgents(DateTime now) async {
    final rows = await _db.query(
      'agents',
      where: 'status = ? AND (nextCheckAt IS NULL OR nextCheckAt <= ?)',
      whereArgs: [AgentStatus.active.name, now.millisecondsSinceEpoch],
    );
    return rows.map(Agent.fromMap).toList();
  }

  @override
  Future<void> logActivity(int agentId, String message, DateTime at) =>
      _db.insert('activity', {
        'agentId': agentId,
        'timestamp': at.millisecondsSinceEpoch,
        'message': message,
      });

  @override
  Future<List<ActivityEntry>> activityFor(
    int agentId, {
    int limit = 100,
  }) async {
    final rows = await _db.query(
      'activity',
      where: 'agentId = ?',
      whereArgs: [agentId],
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(ActivityEntry.fromMap).toList();
  }

  @override
  Future<List<ActivityEntry>> recentActivity({int limit = 50}) async {
    final rows = await _db.query(
      'activity',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(ActivityEntry.fromMap).toList();
  }

  @override
  Future<void> close() => _db.close();
}
