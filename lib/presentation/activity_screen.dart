import 'expressive.dart';
import 'history_cycles.dart';
import 'press_feedback.dart';

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
              child: LookoutPressFeedback(
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
            ),
        ],
      );
    },
  );

  String _scheduleLine(Agent agent) {
    final m = agent.checkInterval.inMinutes;
    final every = m < 60
        ? 'every $m min'
        : (m % 60 == 0 ? 'every ${m ~/ 60} h' : 'every ${(m / 60).toStringAsFixed(1)} h');
    final next = agent.nextCheckAt;
    final nextLine = next == null
        ? 'no check scheduled'
        : (next.isAfter(DateTime.now())
            ? 'next check scheduled for ${fmtHistoryTime(next)}'
            : 'due for a check now');
    return 'Checks $every · $nextLine';
  }

  Widget _taskHistory(int id) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FutureBuilder<Agent?>(
        key: ValueKey('history-label-$id'),
        future: _agent,
        builder: (context, snap) {
          final agent = snap.data;
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${agent?.title ?? 'Task'} · #$id',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (agent != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _scheduleLine(agent),
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      FutureBuilder<List<String?>>(
        key: ValueKey('history-last-run-$id'),
        future: Future.wait([
          widget.repo.getKv('lastBackgroundRunAt'),
          widget.repo.getKv('lastBackgroundError'),
        ]),
        builder: (context, snap) {
          final scheme = Theme.of(context).colorScheme;
          final at = snap.hasData && snap.data![0] != null
              ? DateTime.tryParse(snap.data![0]!)
              : null;
          // App-wide liveness: the worker serves every task, so this line
          // says nothing about whether this particular watch was checked.
          final line = at == null
              ? 'Background worker has no recorded run yet (app-wide).'
              : 'Background worker last ran: ${fmtHistoryTime(at)} (app-wide).';
          final err = snap.hasData ? snap.data![1] : null;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                if (err != null)
                  Text(
                    'Background worker error: $err',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
              ],
            ),
          );
        },
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text('Only this task’s recorded activity. Each card is one check or update.'),
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
            final cycles = groupHistoryCycles(items);
            final interrupted = cycles.any((c) => c.looksInterrupted);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: cycles.length + (interrupted ? 1 : 0),
              itemBuilder: (context, i) {
                if (interrupted && i == 0) {
                  return const _InterruptedBanner();
                }
                final idx = interrupted ? i - 1 : i;
                return CycleCard(cycle: cycles[idx]);
              },
            );
          },
        ),
      ),
    ],
  );
}

class _InterruptedBanner extends StatelessWidget {
  const _InterruptedBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'A check started, but no result was recorded. '
              'The reason is unknown.',
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
