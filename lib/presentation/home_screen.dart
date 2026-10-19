import 'press_feedback.dart';
import '../../update/app_update.dart';

import 'package:flutter/material.dart';

import '../data/agent_repository.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // In-app self-update: check the latest release once after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybePromptUpdate(context);
    });
    _refresh();
  }

  Future<void> _refresh() async {
    final agents = await widget.repo.allAgents();
    if (mounted) {
      setState(() {
        _agents = agents;
        _loading = false;
      });
    }
  }

  int _count(AgentStatus s) => _agents
      .where(
        (a) =>
            a.status == s &&
            !(s == AgentStatus.active && a.needsSourceResolution),
      )
      .length;

  Future<void> _createAgent() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateAgentScreen(repo: widget.repo)),
    );
    _refresh();
  }

  Future<void> _openActivity() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ActivityScreen(repo: widget.repo)),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.visibility_outlined,
                color: colors.onPrimary,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Lookout'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openActivity,
            tooltip: 'Task histories',
            icon: const Icon(Icons.history_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: LookoutPressFeedback(
        child: FloatingActionButton.extended(
          onPressed: _createAgent,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create Agent'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
                    children: [
                      Text(
                        'YOUR PERSONAL WATCHLIST',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your watchlist.',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          height: 1.12,
                          letterSpacing: -1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your reminders and value watches, together.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 16,
                          children: [
                            _SummaryChip(
                              label: 'Active',
                              count: _count(AgentStatus.active),
                            ),
                            if (_agents.any(
                              (a) =>
                                  a.status == AgentStatus.active &&
                                  a.needsSourceResolution,
                            ))
                              _SummaryChip(
                                label: 'Needs source',
                                count: _agents
                                    .where(
                                      (a) =>
                                          a.status == AgentStatus.active &&
                                          a.needsSourceResolution,
                                    )
                                    .length,
                              ),
                            _SummaryChip(
                              label: 'Paused',
                              count: _count(AgentStatus.paused),
                            ),
                            _SummaryChip(
                              label: 'Done',
                              count: _count(AgentStatus.completed),
                            ),
                            _SummaryChip(
                              label: 'Failed',
                              count: _count(AgentStatus.failed),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Your watches',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.5,
                              ),
                            ),
                          ),
                          Text(
                            '${_agents.length} total',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_agents.isEmpty)
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 32,
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.visibility_outlined,
                                  size: 38,
                                  color: colors.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No agents yet.',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Start with a price to watch or a reminder. Tap Create Agent to set it up.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
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
                            onHistory: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ActivityScreen(
                                  repo: widget.repo,
                                  agentId: a.id!,
                                ),
                              ),
                            ),
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
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  const _SummaryChip({required this.label, required this.count});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;
  final VoidCallback onRunNow;
  final VoidCallback onHistory;
  final VoidCallback onPauseResume;
  const _AgentCard({
    required this.agent,
    required this.onTap,
    required this.onRunNow,
    required this.onHistory,
    required this.onPauseResume,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = switch (agent.status) {
      AgentStatus.active => scheme.primary,
      AgentStatus.paused => scheme.tertiary,
      AgentStatus.completed => scheme.primary,
      AgentStatus.failed => scheme.error,
    };
    final number = agent.currentValue;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: LookoutPressFeedback(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      agent.type == AgentType.reminder
                          ? Icons.alarm_rounded
                          : Icons.show_chart_rounded,
                      size: 19,
                      color: scheme.primary,
                    ),
                    Text(
                      agent.typeLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        agent.statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        agent.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  agent.conditionLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (agent.type == AgentType.valueWatch && number != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    agent.isTextWatch
                        ? agent.readingLabel(number)
                        : 'Stored value: ${number == number.roundToDouble() ? number.toInt() : number}',
                    style: theme.textTheme.labelLarge,
                  ),
                ],
                if (agent.lastCheckedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last checked ${_fmt(agent.lastCheckedAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: onRunNow,
                      child: const Text('Run now'),
                    ),
                    TextButton(
                      onPressed: onHistory,
                      child: const Text('History'),
                    ),
                    TextButton(
                      onPressed: onPauseResume,
                      child: Text(
                        agent.status == AgentStatus.paused ? 'Resume' : 'Pause',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
