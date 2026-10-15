import 'package:flutter/material.dart';

import '../data/agent_repository.dart';
import '../domain/activity.dart';
import '../domain/agent.dart';

/// A task chooser, or the history of exactly one persisted task ID.
/// Titles are labels only: duplicate names and renames never merge histories.
class ActivityScreen extends StatefulWidget {
  final AgentRepository repo;
  final int? agentId;
  const ActivityScreen({super.key, required this.repo, this.agentId});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late Future<List<Agent>> _agents;
  late Future<List<ActivityEntry>> _activity;
  late Future<Agent?> _agent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ActivityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repo != widget.repo || oldWidget.agentId != widget.agentId) {
      _load();
    }
  }

  void _load() {
    final id = widget.agentId;
    _agents = id == null ? widget.repo.allAgents() : Future.value(<Agent>[]);
    _agent = id == null ? Future.value(null) : widget.repo.agentById(id);
    _activity = id == null
        ? Future.value(<ActivityEntry>[])
        : widget.repo.activityFor(id, limit: 200);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.agentId;
    return Scaffold(
      appBar: AppBar(
        title: Text(id == null ? 'Task histories' : 'Task history'),
      ),
      body: id == null ? _taskChooser() : _taskHistory(id),
    );
  }

  Widget _taskChooser() => FutureBuilder<List<Agent>>(
    future: _agents,
    builder: (context, snap) {
      if (snap.hasError) {
        return const Center(child: Text('Could not load tasks.'));
      }
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final tasks = snap.data!;
      if (tasks.isEmpty) {
        return const Center(
          child: Text('No tasks yet. Create an agent to get started.'),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Choose a task to see only its activity.'),
          const SizedBox(height: 16),
          for (final task in tasks)
            Card(
              child: ListTile(
                key: ValueKey('history-task-${task.id}'),
                title: Text(task.title),
                subtitle: Text('Task #${task.id} · ${task.statusLabel}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ActivityScreen(repo: widget.repo, agentId: task.id!),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _taskHistory(int id) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FutureBuilder<Agent?>(
        key: ValueKey('history-label-$id'),
        future: _agent,
        builder: (context, snap) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            '${snap.data?.title ?? 'Task'} · #$id',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text('Only this task’s recorded activity. Latest 200 entries.'),
      ),
      Expanded(
        child: FutureBuilder<List<ActivityEntry>>(
          // A new identity gets a fresh builder, with no previous task's data.
          key: ValueKey('history-events-$id'),
          future: _activity,
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(
                child: Text('Could not load this task’s history.'),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data!
                .where((entry) => entry.agentId == id)
                .toList();
            if (items.isEmpty) {
              return const Center(
                child: Text('No activity recorded for this task yet.'),
              );
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final entry = items[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.bolt, size: 18),
                  title: Text(entry.message),
                  subtitle: Text(_fmt(entry.timestamp)),
                );
              },
            );
          },
        ),
      ),
    ],
  );

  static String _fmt(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
