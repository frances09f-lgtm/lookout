import 'dart:async';

import 'press_feedback.dart';
import 'expressive.dart';
import '../../update/app_update.dart';

import 'package:flutter/material.dart';

import '../data/agent_repository.dart';
import '../domain/agent.dart';
import '../domain/time_format.dart';
import '../services/checker.dart';
import 'activity_screen.dart';
import 'agent_details_screen.dart';
import 'create_agent_screen.dart';

class HomeScreen extends StatefulWidget {
  final AgentRepository repo;
  final AgentChecker checker;
  final bool isDark;
  final ValueChanged<bool> onToggleTheme;

  static void _noopTheme(bool _) {}

  const HomeScreen(
      {super.key,
      required this.repo,
      required this.checker,
      this.isDark = false,
      this.onToggleTheme = _noopTheme});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  List<Agent> _agents = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // In-app self-update: check the latest release once after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybePromptUpdate(context);
    });
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the app re-evaluates completion expiries.
    if (state == AppLifecycleState.resumed) _refresh();
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

  /// Completed cards leave the watchlist the moment they complete - the
  /// user asked for completed tasks to be removed immediately, every time.
  /// Removing the card never deletes the record: History keeps it.
  bool _staysOnWatchlist(Agent a) => a.status != AgentStatus.completed;

  int _count(AgentStatus s) => _agents
      .where(
        (a) =>
            a.status == s &&
            !(s == AgentStatus.active && a.needsSourceResolution),
      )
      .length;

  Future<void> _createAgent() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreateAgentScreen(repo: widget.repo)),
    );
    _refresh();
    // Creation is confirmed explicitly: the create flow can also end with
    // no task (review abandoned, revalidation failed), and the two endings
    // must not look alike.
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task created')),
      );
    }
  }

  Future<void> _openActivity() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ActivityScreen(repo: widget.repo)),
    );
    _refresh();
  }

  Widget _summaryPill(String label, int count, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$count',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsSource = _agents
        .where((a) => a.status == AgentStatus.active && a.needsSourceResolution)
        .length;
    return Scaffold(
      bottomNavigationBar: XDock(
        selected: 0,
        onSelect: (i) {
          if (i == 1) _openActivity();
        },
        onCreate: _createAgent,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: xInk(context),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(Icons.visibility_rounded,
                                  color: xIsDark(context)
                                      ? XColors.ink
                                      : Colors.white,
                                  size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Lookout',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.8)),
                            ),
                            IconButton(
                              onPressed: () =>
                                  widget.onToggleTheme(!widget.isDark),
                              tooltip: widget.isDark
                                  ? 'Switch to light mode'
                                  : 'Switch to dark mode',
                              icon: Icon(
                                widget.isDark
                                    ? Icons.wb_sunny_rounded
                                    : Icons.dark_mode_rounded,
                                color: xInkSoft(context),
                              ),
                            ),
                            IconButton(
                              onPressed: () => checkUpdateManually(context),
                              tooltip: 'Check for updates',
                              icon: Icon(
                                  Icons.system_update_alt_rounded,
                                  color: xInkSoft(context)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Your watchlist.',
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontSize: 34,
                            height: 1.05,
                            letterSpacing: -1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Your reminders and value watches, together.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: xInkSoft(context),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _summaryPill('Active', _count(AgentStatus.active),
                                XColors.mint, XColors.mintDeep),
                            if (needsSource > 0)
                              _summaryPill(
                                  'Needs source',
                                  needsSource,
                                  XColors.lemon,
                                  XColors.lemonDeep),
                            _summaryPill('Paused', _count(AgentStatus.paused),
                                XColors.peach, XColors.peachDeep),
                            _summaryPill(
                                'Done',
                                _count(AgentStatus.completed),
                                XColors.lavender,
                                XColors.lavenderDeep),
                            if (_count(AgentStatus.failed) > 0)
                              _summaryPill(
                                  'Failed',
                                  _count(AgentStatus.failed),
                                  theme.colorScheme.errorContainer,
                                  theme.colorScheme.onErrorContainer),
                          ],
                        ),
                        const SizedBox(height: 26),
                        Row(
                          children: [
                            Expanded(
                              child: xSectionLabel(
                                  'Watching now', xMintOnCanvas(context)),
                            ),
                            Text(
                              '${_agents.length} total',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: xInkSoft(context),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (_agents.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 32),
                            decoration: BoxDecoration(
                              color: XColors.lavender,
                              borderRadius: BorderRadius.circular(32),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.visibility_outlined,
                                    size: 38, color: XColors.lavenderDeep),
                                const SizedBox(height: 16),
                                Text(
                                  'No agents yet.',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: XColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Start with a price to watch or a reminder. Tap + below to set it up.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: XColors.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ..._agents
                              .where((a) => _staysOnWatchlist(a))
                              .map(
                            (a) => AgentCard(
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
      ),
    );
  }
}

class AgentCard extends StatelessWidget {
  final Agent agent;
  final VoidCallback onTap;
  final VoidCallback onRunNow;
  final VoidCallback onHistory;
  final VoidCallback onPauseResume;
  const AgentCard({
    required this.agent,
    required this.onTap,
    required this.onRunNow,
    required this.onHistory,
    required this.onPauseResume,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = agent.status == AgentStatus.active;
    final toggleable = running || agent.status == AgentStatus.paused;
    final isDark = xIsDark(context);
    final pastel = XColors.pastelFor(agent.id ?? agent.title.hashCode);
    // Approved dark-mode look: every card sits on a dark panel; light mode
    // keeps pastel fills for running watches. In dark mode the accent is the
    // light pastel so values and actions read on the panel.
    final (bg, accent) = running
        ? (isDark ? xPanel(context) : pastel.$1, isDark ? pastel.$1 : pastel.$2)
        : agent.status == AgentStatus.paused
            ? (xPanel(context), isDark ? XColors.peach : XColors.peachDeep)
            : (xPanel(context), XColors.inkSoft);
    // True only for a light-mode running card (dark text on pastel fill).
    final onPastel = running && !isDark;
    final number = agent.currentValue;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(32),
      ),
      child: LookoutPressFeedback(
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark && running ? pastel.$2 : accent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        agent.type == AgentType.reminder
                            ? Icons.alarm_rounded
                            : Icons.show_chart_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        agent.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: onPastel ? XColors.ink : xInk(context),
                        ),
                      ),
                    ),
                    if (toggleable)
                      xSwitch(
                        value: running,
                        accent: accent,
                        accentDark: pastel.$2,
                        onChanged: (_) => onPauseResume(),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: xTrack(context),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          agent.statusLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: xInkSoft(context),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${agent.typeLabel} · ${agent.conditionLabel}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: onPastel ? XColors.inkSoft : xInkSoft(context),
                  ),
                ),
                if (agent.type == AgentType.valueWatch && number != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _fmtValue(number),
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          color: running
                              ? accent
                              : (isDark ? xInk(context) : XColors.inkSoft),
                        ),
                      ),
                      if (agent.lastCheckedAt != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              'last checked ${_fmt(agent.lastCheckedAt!)}',
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: onPastel ? XColors.inkSoft : xInkSoft(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else if (agent.lastCheckedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last checked ${_fmt(agent.lastCheckedAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: XColors.inkSoft,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  children: [
                    // Light-mode pastel cards use dark ink; dark-mode panel
                    // cards use the accent (mint/peach pastel) so actions
                    // read on the dark fill. Completed cards ghost Run now.
                    TextButton(
                      onPressed: agent.status == AgentStatus.completed
                          ? null
                          : onRunNow,
                      style: TextButton.styleFrom(
                        foregroundColor: onPastel
                            ? XColors.ink
                            : (toggleable ? accent : xInk(context)),
                        disabledForegroundColor: onPastel
                            ? XColors.inkSoft
                            : xInkSoft(context),
                      ),
                      child: const Text('Run now'),
                    ),
                    TextButton(
                      onPressed: onHistory,
                      style: TextButton.styleFrom(
                        foregroundColor: onPastel
                            ? XColors.ink
                            : isDark
                                ? (toggleable
                                    ? accent
                                    : xMintOnCanvas(context))
                                : XColors.ink,
                      ),
                      child: const Text('History'),
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

  /// Thousands-grouped, at most 2 decimals: 80199.0223364612 -> 80,199.02.
  static String _fmtValue(double v) {
    final neg = v < 0;
    final abs = v.abs();
    final text =
        abs == abs.roundToDouble() ? '${abs.toInt()}' : abs.toStringAsFixed(2);
    final dot = text.indexOf('.');
    final intPart = dot < 0 ? text : text.substring(0, dot);
    final grouped = intPart.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '${neg ? '-' : ''}$grouped${dot < 0 ? '' : text.substring(dot)}';
  }

  static String _fmt(DateTime t) => fmtAppTime(t);
}
