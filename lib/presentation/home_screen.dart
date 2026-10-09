import 'package:flutter/material.dart';

import '../data/agent_repository.dart';
import '../domain/activity.dart';
import '../domain/agent.dart';
import '../services/checker.dart';
import 'activity_screen.dart';
import 'agent_details_screen.dart';
import 'create_agent_screen.dart';

class HomeScreen extends StatefulWidget {
  final AgentRepository repo;
  final AgentChecker checker;

  const HomeScreen({super.key, required this.repo, required this.checker});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _recovering = false;
  String _recoveryNote =
      'Background checks are Android best-effort, at least15 minutes apart.';
  List<Agent> _agents = [];
  List<ActivityEntry> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recover();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recover();
  }

  Future<void> _recover() async {
    if (_recovering) return;
    _recovering = true;
    if (mounted) setState(() => _recoveryNote = 'Checking overdue watches...');
    try {
      final count = await widget.checker.checkDueAgents();
      if (mounted)
        setState(
          () => _recoveryNote =
              'Recovered $count due checks. Background checks are best-effort, at least15 minutes apart.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _recoveryNote = 'Overdue check failed. Pull to retry; check Activity for source errors.',
        );
    } finally {
      _recovering = false;
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    final agents = await widget.repo.allAgents();
    final recent = await widget.repo.recentActivity(limit: 10);
    if (mounted) {
      setState(() {
        _agents = agents;
        _recent = recent;
        _loading = false;
      });
    }
  }

  int _count(AgentStatus s) => _agents.where((a) => a.status == s).length;

  @override
  Widget build(BuildContext context) {
    final active = _count(AgentStatus.active);
    final paused = _count(AgentStatus.paused);
    final completed = _count(AgentStatus.completed);
    final failed = _count(AgentStatus.failed);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Lookout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Activity log',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActivityScreen(repo: widget.repo),
                ),
              );
              _refresh();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2979FF),
        foregroundColor: Colors.white,
        tooltip: 'Create agent',
        shape: const CircleBorder(),
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CreateAgentScreen(repo: widget.repo),
            ),
          );
          _refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _recover,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _recoveryNote,
                    style: const TextStyle(
                      color: Color(0xFFB6B6B6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _SummaryChip(label: 'Active', count: active),
                      _SummaryChip(label: 'Paused', count: paused),
                      _SummaryChip(label: 'Done', count: completed),
                      _SummaryChip(label: 'Failed', count: failed),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_agents.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          'No agents yet.\nTap + and tell Lookout what to watch.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._agents.map(
                      (a) => _AgentCard(
                        agent: a,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AgentDetailsScreen(
                                repo: widget.repo,
                                checker: widget.checker,
                                agentId: a.id!,
                              ),
                            ),
                          );
                          _refresh();
                        },
                        onRunNow: () async {
                          await widget.checker.checkAgent(a);
                          _refresh();
                        },
                        onPauseResume: () async {
                          await widget.repo.updateAgent(
                            a.copyWith(
                              status: a.status == AgentStatus.paused
                                  ? AgentStatus.active
                                  : AgentStatus.paused,
                            ),
                          );
                          _refresh();
                        },
                      ),
                    ),
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Recent activity',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ..._recent.map(
                      (e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bolt, size: 18),
                        title: Text(e.message),
                        subtitle: Text(_fmtTime(e.timestamp)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  static String _fmtTime(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  const _SummaryChip({required this.label, required this.count});
  Color get color => switch (label) {
    'Active' => const Color(0xFF54F29A),
    'Paused' => const Color(0xFFFFC857),
    'Done' => const Color(0xFF66A6FF),
    _ => const Color(0xFFFF6575),
  };

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFFB6B6B6), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;
  final VoidCallback onRunNow;
  final VoidCallback onPauseResume;

  const _AgentCard({
    required this.agent,
    required this.onTap,
    required this.onRunNow,
    required this.onPauseResume,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (agent.status) {
      AgentStatus.active => const Color(0xFF54F29A),
      AgentStatus.paused => const Color(0xFFFFC857),
      AgentStatus.completed => const Color(0xFF66A6FF),
      AgentStatus.failed => const Color(0xFFFF6575),
    };
    final checked = agent.lastCheckedAt;
    String age() {
      if (checked == null) return 'Not checked yet';
      final d = DateTime.now().difference(checked);
      if (d.isNegative) return 'Checked ${_fmt(checked)}';
      if (d.inMinutes < 1) return 'Checked just now';
      if (d.inHours < 1) return 'Checked ${d.inMinutes}m ago';
      if (d.inDays < 1) return 'Checked ${d.inHours}h ago';
      return 'Checked ${d.inDays}d ago';
    }

    Widget badge(String text, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: c, fontSize: 11)),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          agent.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          agent.conditionLabel,
                          style: const TextStyle(
                            color: Color(0xFFB6B6B6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Run now',
                    onPressed: onRunNow,
                    icon: const Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFFD6D6D6),
                    ),
                  ),
                  IconButton(
                    tooltip: agent.status == AgentStatus.paused
                        ? 'Resume'
                        : 'Pause',
                    onPressed: onPauseResume,
                    icon: Icon(
                      agent.status == AgentStatus.paused
                          ? Icons.play_circle_outline
                          : Icons.pause_rounded,
                      color: const Color(0xFFD6D6D6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                valueProvenance(agent, DateTime.now()),
                style: const TextStyle(color: Color(0xFFB6B6B6), fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  badge(
                    agent.status == AgentStatus.completed
                        ? 'Done'
                        : agent.statusLabel,
                    color,
                  ),
                  badge(age(), const Color(0xFFB6B6B6)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String valueProvenance(Agent agent, DateTime now) {
  if (agent.type == AgentType.reminder)
    return 'Reminder uses the device clock.';
  final at = agent.lastSuccessfulReadAt;
  if (at == null)
    return agent.currentValue == null
        ? 'No fresh value available. Set a source or manual value.'
        : 'Saved/manual value only: ${agent.currentValue}. Not a live price.';
  final age = now.difference(at);
  final fresh = age >= Duration.zero && age <= const Duration(minutes: 5);
  return '${fresh ? 'Recent successful read' : 'Stale saved read'}: ${agent.lastSuccessfulValue ?? agent.currentValue}, ${age.isNegative ? 0 : age.inMinutes}m ago. Not a live stream.';
}
