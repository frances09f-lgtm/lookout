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

class _HomeScreenState extends State<HomeScreen> {
  List<Agent> _agents = [];
  List<ActivityEntry> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
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
      appBar: AppBar(
        title: const Text('Lookout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Activity log',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ActivityScreen(repo: widget.repo)));
              _refresh();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => CreateAgentScreen(repo: widget.repo)));
          _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Agent'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(children: [
                    _SummaryChip(label: 'Active', count: active),
                    _SummaryChip(label: 'Paused', count: paused),
                    _SummaryChip(label: 'Done', count: completed),
                    _SummaryChip(label: 'Failed', count: failed),
                  ]),
                  const SizedBox(height: 16),
                  if (_agents.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          'No agents yet.\nTap Create Agent and tell Lookout what to watch.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    ..._agents.map((a) => _AgentCard(
                          agent: a,
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => AgentDetailsScreen(
                                    repo: widget.repo,
                                    checker: widget.checker,
                                    agentId: a.id!)));
                            _refresh();
                          },
                          onRunNow: () async {
                            await widget.checker.checkAgent(a);
                            _refresh();
                          },
                          onPauseResume: () async {
                            await widget.repo.updateAgent(a.copyWith(
                                status: a.status == AgentStatus.paused
                                    ? AgentStatus.active
                                    : AgentStatus.paused));
                            _refresh();
                          },
                        )),
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Recent activity',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._recent.map((e) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.bolt, size: 18),
                          title: Text(e.message),
                          subtitle: Text(_fmtTime(e.timestamp)),
                        )),
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

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(children: [
            Text('$count',
                style: Theme.of(context).textTheme.titleLarge),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ]),
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
    final icon = agent.type == AgentType.reminder
        ? Icons.alarm
        : Icons.trending_down;
    final scheme = Theme.of(context).colorScheme;
    final statusColor = switch (agent.status) {
      AgentStatus.active => scheme.primary,
      AgentStatus.paused => scheme.tertiary,
      AgentStatus.completed => Colors.green,
      AgentStatus.failed => scheme.error,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(agent.title,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              Text(agent.statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            Text(agent.conditionLabel,
                style: Theme.of(context).textTheme.bodySmall),
            if (agent.lastCheckedAt != null)
              Text('Last checked ${_fmt(agent.lastCheckedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: onRunNow, child: const Text('Run now')),
              TextButton(
                onPressed: onPauseResume,
                child: Text(
                    agent.status == AgentStatus.paused ? 'Resume' : 'Pause'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
