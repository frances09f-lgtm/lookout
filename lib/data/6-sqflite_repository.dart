/// SQLite-backed repository (spec V1: SQLite/Drift or Isar, local-first).
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/agent.dart';
import '../domain/activity.dart';
import 'agent_repository.dart';

class SqfliteAgentRepository implements AgentRepository {
  static const _dbName = 'lookout.db';
  static const _dbVersion = 7;

  final Database _db;

  SqfliteAgentRepository._(this._db);

  static Future<SqfliteAgentRepository> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), _dbName);
    final db = await openDatabase(
      dbPath,
      version: _dbVersion,
      // Every opener gets its OWN native connection. The default
      // (singleInstance: true) shares one native connection per path
      // process-wide across Flutter engines, so the Workmanager isolate's
      // close() used to break the foreground app's live database - every
      // later read threw DatabaseException(database_closed), the task
      // history failure in v1.1.13 (tekartik/sqflite#558).
      singleInstance: false,
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
            completedAt INTEGER,
            nextCheckAt INTEGER,
            checkIntervalMinutes INTEGER NOT NULL,
            condition TEXT NOT NULL,
            target REAL NOT NULL,
            currentValue REAL,
            previousValue REAL,
            sourceUrl TEXT,
            sourceIdentity TEXT,
            lastSuccessfulReadAt INTEGER,
            lastSuccessfulValue REAL,
            lastReadMethod TEXT,
            lastReadSourceUrl TEXT,
            notificationEnabled INTEGER NOT NULL DEFAULT 1,
            consecutiveSourceBlocks INTEGER NOT NULL DEFAULT 0
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
        await db.execute(
          'CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 7) {
          await db.execute(
            'ALTER TABLE agents ADD COLUMN consecutiveSourceBlocks INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE agents ADD COLUMN completedAt INTEGER');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE agents ADD COLUMN sourceIdentity TEXT');
        }
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
    // The background worker keeps its own connection to this file. Without
    // a busy timeout a read that races one of its writes fails instantly
    // with SQLITE_BUSY - which is how a history screen shows "Could not
    // load" while the data is fine. Wait briefly instead.
    // rawQuery, not execute: this PRAGMA returns a row, and
    // execSQL-backed execute() rejects row-returning statements on
    // some Android versions - a throw here hangs startup on the logo.
    await db.rawQuery('PRAGMA busy_timeout = 4000');
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
      where: 'status = ? AND consecutiveSourceBlocks < ? AND (nextCheckAt IS NULL OR nextCheckAt <= ?)',
      whereArgs: [
        AgentStatus.active.name,
        Agent.sourceBlockThreshold,
        now.millisecondsSinceEpoch,
      ],
      // Never-checked first, then most overdue first (SQLite sorts NULLs
      // first in ASC), so a time-budgeted sweep is fair.
      orderBy: 'nextCheckAt ASC',
    );
    return rows
        .map(Agent.fromMap)
        .where((a) => !a.needsSourceResolution)
        .toList();
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
    return rows
        .map(ActivityEntry.tryFromMap)
        .whereType<ActivityEntry>()
        .toList();
  }

  @override
  Future<List<ActivityEntry>> recentActivity({int limit = 50}) async {
    final rows = await _db.query(
      'activity',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows
        .map(ActivityEntry.tryFromMap)
        .whereType<ActivityEntry>()
        .toList();
  }

  @override
  Future<void> putKv(String key, String value) async {
    await _db.insert(
      'kv',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<String?> getKv(String key) async {
    final rows = await _db.query(
      'kv',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> close() => _db.close();
}
