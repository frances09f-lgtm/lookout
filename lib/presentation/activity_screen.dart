import 'expressive.dart';
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
        child: Text('Only this task’s recorded activity. One card per check.'),
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
            final cycles = _groupCycles(items);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: cycles.length,
              itemBuilder: (context, i) => _CycleCard(cycle: cycles[i]),
            );
          },
        ),
      ),
    ],
  );

  /// One card per check cycle: every log line a cycle writes shares the exact
  /// same timestamp (checker passes one `at` to all its logActivity calls).
  static List<_Cycle> _groupCycles(List<ActivityEntry> items) {
    final byStamp = <int, List<ActivityEntry>>{};
    for (final e in items) {
      byStamp.putIfAbsent(e.timestamp.millisecondsSinceEpoch, () => []).add(e);
    }
    return [
      for (final entries in byStamp.values)
        _Cycle(
          // Ids are monotonic in write order, so a cycle's lines read in the
          // order they happened (list sort is not stable on equal times).
          entries: entries..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0)),
        ),
    ];
  }

  static String _fmt(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// The honest outcome of one check cycle, derived only from what was logged.
enum _CycleState { noResult, failed, notMet, met }

class _Cycle {
  final List<ActivityEntry> entries;
  _Cycle({required this.entries});

  DateTime get at => entries.first.timestamp;

  bool _has(String prefix) => entries.any((e) => e.message.startsWith(prefix));

  _CycleState get state {
    if (_has('Unable to check')) return _CycleState.failed;
    if (_has('Condition met')) return _CycleState.met;
    if (_has('Condition not met')) return _CycleState.notMet;
    return _CycleState.noResult;
  }

  String get title => switch (state) {
    _CycleState.failed => 'Unable to check',
    _CycleState.met => 'Condition met',
    _CycleState.notMet => 'Condition not met',
    _CycleState.noResult => 'Started check',
  };

  String get badge => switch (state) {
    _CycleState.failed => 'Failed',
    _CycleState.met => 'Done',
    _CycleState.notMet => 'Not yet',
    _CycleState.noResult => 'No result',
  };

  (Color, Color) get colors => switch (state) {
    _CycleState.failed => (XColors.peach, XColors.peachDeep),
    _CycleState.met => (XColors.mint, XColors.mintDeep),
    _CycleState.notMet => (XColors.sky, XColors.skyDeep),
    _CycleState.noResult => (XColors.lavender, XColors.lavenderDeep),
  };

  IconData get icon => switch (state) {
    _CycleState.failed => Icons.warning_amber_rounded,
    _CycleState.met => Icons.check_circle_outline,
    _CycleState.notMet => Icons.check,
    _CycleState.noResult => Icons.bolt,
  };

  /// Log lines shown inside the card. The state line itself is dropped (the
  /// title and badge already say it); its detail is kept without the prefix.
  List<_Step> get steps {
    final out = <_Step>[];
    for (final e in entries) {
      final m = e.message;
      if (m == 'Condition met' || m == 'Condition not met') continue;
      if (m == 'Started check' && state == _CycleState.noResult) continue;
      if (m.startsWith('Unable to check: ')) {
        out.add(
          _Step(m.substring('Unable to check: '.length), _StepKind.value),
        );
      } else if (m.startsWith('Next check scheduled')) {
        out.add(_Step(m, _StepKind.next));
      } else if (m.startsWith('Read retry scheduled')) {
        out.add(_Step(m, _StepKind.retry));
      } else if (m.startsWith('Fetched data') ||
          m.startsWith('Clock checked') ||
          m.startsWith('Manual value checked')) {
        out.add(_Step(m, _StepKind.value));
      } else {
        out.add(_Step(m, _StepKind.normal));
      }
    }
    if (state == _CycleState.noResult && out.isEmpty) {
      out.add(
        const _Step('No result recorded for this cycle', _StepKind.normal),
      );
    }
    return out;
  }
}

enum _StepKind { normal, value, next, retry }

class _Step {
  final String text;
  final _StepKind kind;
  const _Step(this.text, this.kind);
}

class _CycleCard extends StatelessWidget {
  final _Cycle cycle;
  const _CycleCard({required this.cycle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (pastel, deep) = cycle.colors;
    final dark = xIsDark(context);
    final nextColor = dark ? const Color(0xFF8FC3EE) : XColors.skyDeep;
    final retryColor = dark ? const Color(0xFFF0B98A) : XColors.peachDeep;
    final isNoResult = cycle.state == _CycleState.noResult;
    final badgeBg = isNoResult
        ? theme.colorScheme.surfaceContainerHighest
        : pastel;
    final badgeFg = isNoResult ? theme.colorScheme.onSurfaceVariant : deep;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
      decoration: BoxDecoration(
        color: xPanel(context),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: pastel,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(cycle.icon, size: 18, color: deep),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cycle.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _ActivityScreenState._fmt(cycle.at),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  cycle.badge.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: badgeFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 9),
          for (final step in cycle.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      step.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        height: 1.35,
                        color: switch (step.kind) {
                          _StepKind.value => theme.colorScheme.onSurface,
                          _StepKind.next => nextColor,
                          _StepKind.retry => retryColor,
                          _StepKind.normal =>
                            theme.colorScheme.onSurfaceVariant,
                        },
                        fontWeight: switch (step.kind) {
                          _StepKind.value => FontWeight.w600,
                          _StepKind.next => FontWeight.w700,
                          _StepKind.retry => FontWeight.w700,
                          _StepKind.normal => FontWeight.w400,
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
