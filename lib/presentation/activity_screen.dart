import 'expressive.dart';
import 'history_cycles.dart';
import 'press_feedback.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/agent_repository.dart';
import '../domain/activity.dart';
import '../domain/agent.dart';
import '../services/background.dart';

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
  late Future<_BackgroundStatus> _backgroundStatus;

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
    _backgroundStatus = id == null
        ? Future.value(const _BackgroundStatus())
        : _loadBackgroundStatus();
  }

  /// Worker liveness from the kv store, falling back to the
  /// SharedPreferences mirror the dispatcher also writes. The mirror
  /// survives a broken database, and a READ FAILURE is shown as itself -
  /// never masked as "no recorded run yet".
  Future<_BackgroundStatus> _loadBackgroundStatus() async {
    String? startedRaw, completedRaw, error, note;
    Object? readError;
    try {
      startedRaw = await widget.repo.getKv('lastBackgroundRunStartedAt');
      completedRaw = await widget.repo.getKv('lastBackgroundRunAt');
      error = await widget.repo.getKv('lastBackgroundError');
      note = await widget.repo.getKv('lastBackgroundNote');
    } catch (e) {
      readError = e;
    }
    try {
      // The mirror must never block the screen: if preferences cannot be
      // read quickly (missing plugin, wedged channel), show what kv gave.
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      startedRaw ??= prefs.getString(prefLastStartedAt);
      completedRaw ??= prefs.getString(prefLastCompletedAt);
      error ??= prefs.getString(prefLastError);
      note ??= prefs.getString(prefLastNote);
    } catch (_) {
      // No mirror either; whatever the store gave is all there is.
    }
    final completed =
        completedRaw == null ? null : DateTime.tryParse(completedRaw);
    return _BackgroundStatus(
      started: startedRaw == null ? null : DateTime.tryParse(startedRaw),
      completed: completed,
      error: currentWorkerError(error, completed),
      note: (note == null || note.isEmpty) ? null : note,
      readError: readError,
    );
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
            ? 'next check due from ${fmtHistoryTime(next)}'
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
                  if (agent.checkInterval < const Duration(minutes: 15) &&
                      agent.nextCheckAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Background checks may run later than the due time.',
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ] else if (snap.hasError) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Task details could not be read: ${snap.error}',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                ] else if (snap.connectionState == ConnectionState.done) ...[
                  const SizedBox(height: 4),
                  Text(
                    'This task was deleted; only its recorded activity remains.',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      FutureBuilder<_BackgroundStatus>(
        key: ValueKey('history-last-run-$id'),
        future: _backgroundStatus,
        builder: (context, snap) {
          final scheme = Theme.of(context).colorScheme;
          if (!snap.hasData) return const SizedBox.shrink();
          final st = snap.data!;
          // App-wide liveness: the worker serves every task, so these lines
          // say nothing about whether this particular watch was checked.
          final Widget line;
          if (st.readError != null &&
              st.started == null &&
              st.completed == null) {
            line = Text(
              'Background worker status could not be read: ${_redactDiagnostic('${st.readError}')}',
              style: TextStyle(fontSize: 12, color: scheme.error),
            );
          } else if (st.completed != null) {
            line = Text(
              'Background worker last completed: ${fmtHistoryTime(st.completed!)} (app-wide).',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            );
          } else if (st.started != null) {
            line = Text(
              'Background worker last started: ${fmtHistoryTime(st.started!)}, but no completed run was recorded (app-wide).',
              style: TextStyle(fontSize: 12, color: scheme.error),
            );
          } else {
            line = Text(
              'Background worker has no recorded run yet (app-wide).',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line,
                if (st.note != null)
                  Text(
                    st.note!,
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                if (st.error != null) WorkerProblemLine(raw: st.error!),
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
              final scheme = Theme.of(context).colorScheme;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load this task’s history.'),
                      const SizedBox(height: 8),
                      // The error stays on screen so a screenshot names the
                      // actual failure - with links and file paths redacted,
                      // since a screenshot can travel.
                      Text(
                        _redactDiagnostic('${snap.error}'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
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


/// Error text for the screen: keeps the failure class and wording, drops
/// anything that could expose a watched link or a device path.
/// The stored worker error worth showing, or null. Errors are stored as
/// `<ISO time> <message>`. One recorded at or before the last completed run
/// is history - a later run succeeded - so it is not shown (the Oct 25
/// permission error stayed on screen for days under fresh successful runs).
String? currentWorkerError(String? stored, DateTime? lastCompleted) {
  if (stored == null || stored.trim().isEmpty) return null;
  final at = workerErrorTime(stored);
  if (at != null && lastCompleted != null && !at.isAfter(lastCompleted)) {
    return null;
  }
  return stored;
}

DateTime? workerErrorTime(String stored) {
  final space = stored.indexOf(' ');
  if (space <= 0) return null;
  return DateTime.tryParse(stored.substring(0, space));
}

/// A short, calm line for the last background problem; the raw text sits
/// behind "Details" for anyone who wants to send it on.
class WorkerProblemLine extends StatefulWidget {
  final String raw;
  const WorkerProblemLine({super.key, required this.raw});

  @override
  State<WorkerProblemLine> createState() => _WorkerProblemLineState();
}

class _WorkerProblemLineState extends State<WorkerProblemLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final at = workerErrorTime(widget.raw);
    final message = at == null
        ? widget.raw
        : widget.raw.substring(widget.raw.indexOf(' ') + 1);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('worker-problem-toggle'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.tertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      at == null
                          ? 'Last check had a problem'
                          : 'Last check had a problem (${fmtHistoryTime(at)})',
                      style: TextStyle(fontSize: 12, color: scheme.onSurface),
                    ),
                  ),
                  Text(
                    _open ? 'Hide' : 'Details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: scheme.primary),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              key: const ValueKey('worker-problem-details'),
              width: double.infinity,
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _redactDiagnostic(message, max: 1200),
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _redactDiagnostic(String raw, {int max = 300}) {
  var out = raw.replaceAll(RegExp(r'https?://\S+'), '<link>');
  out = out.replaceAll(RegExp(r'(/[A-Za-z0-9_.-]+){2,}[A-Za-z0-9_/.-]*'), '<path>');
  return out.length > max ? '${out.substring(0, max)}...' : out;
}

/// Snapshot of worker liveness for the history screen.
class _BackgroundStatus {
  final DateTime? started;
  final DateTime? completed;
  final String? error;
  final String? note;

  /// Set when reading the status itself failed; shown honestly instead of
  /// the "no recorded run" empty state.
  final Object? readError;

  const _BackgroundStatus({
    this.started,
    this.completed,
    this.error,
    this.note,
    this.readError,
  });
}
