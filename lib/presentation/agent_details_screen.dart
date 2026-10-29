import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/agent_repository.dart';
import '../domain/activity.dart';
import '../domain/time_format.dart';
import '../domain/agent.dart';
import '../domain/parser.dart';
import '../services/checker.dart';
import '../services/browser_price_check.dart';
import '../services/page_fetch.dart';
import 'activity_screen.dart';
import 'history_cycles.dart';
import 'expressive.dart';
import 'source_review_screen.dart';
import '../services/source_discovery.dart';

class AgentDetailsScreen extends StatefulWidget {
  final AgentRepository repo;
  final AgentChecker checker;
  final int agentId;
  final SourceDiscoveryService? discovery;

  const AgentDetailsScreen({
    super.key,
    required this.repo,
    required this.checker,
    required this.agentId,
    this.discovery,
  });

  @override
  State<AgentDetailsScreen> createState() => _AgentDetailsScreenState();
}

class _AgentDetailsScreenState extends State<AgentDetailsScreen> {
  static const _intervalOptions = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 3),
    Duration(hours: 6),
    Duration(hours: 12),
    Duration(hours: 24),
  ];

  Agent? _agent;
  List<ActivityEntry> _activity = [];
  Duration? _selectedInterval;
  bool _savingInterval = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant AgentDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.agentId != widget.agentId || oldWidget.repo != widget.repo) {
      _agent = null;
      _activity = [];
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final id = widget.agentId;
    final repo = widget.repo;
    final a = await repo.agentById(id);
    if (!mounted || id != widget.agentId || repo != widget.repo) return;
    if (a == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final log = await repo.activityFor(id);
    if (mounted && id == widget.agentId && repo == widget.repo) {
      setState(() {
        _agent = a;
        _activity = log.where((entry) => entry.agentId == id).toList();
        _selectedInterval ??= a.checkInterval;
      });
    }
  }

  static String _intervalChipLabel(Duration d) => d.inMinutes < 60
      ? '${d.inMinutes} min'
      : d.inHours < 24
      ? '${d.inHours} h'
      : '${d.inDays} day';

  /// Saves the chosen interval and reschedules the next check from now.
  /// Existing intervals are never touched unless the user saves here.
  Future<void> _saveInterval() async {
    final a = _agent;
    final interval = _selectedInterval;
    if (a == null || interval == null || _savingInterval) return;
    setState(() => _savingInterval = true);
    try {
      await widget.repo.updateAgent(
        a.copyWith(
          checkInterval: interval,
          nextCheckAt: DateTime.now().add(interval),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingInterval = false);
    }
    _refresh();
  }

  Future<void> _updateValue() async {
    final controller = TextEditingController(
      text: _agent?.currentValue?.toString() ?? '',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update current value'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Current value'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              double.tryParse(controller.text.replaceAll(',', '')),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null && _agent != null) {
      await widget.repo.updateAgent(
        _agent!.copyWith(
          previousValue: _agent!.currentValue,
          currentValue: value,
          lastSuccessfulReadAt: DateTime.now(),
          lastSuccessfulValue: value,
          lastReadMethod: 'Manual value entry',
          lastReadSourceUrl: '',
        ),
      );
      await widget.repo.logActivity(
        widget.agentId,
        'Value updated to $value',
        DateTime.now(),
      );
      _refresh();
    }
  }

  Future<void> _editTarget() async {
    final controller = TextEditingController(
      text: _agent?.target.toString() ?? '',
    );
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Edit target'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Notify below / above',
                errorText: error,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  // Accept the way people actually type money: "₹200",
                  // "200 rs", "1,500". An unparseable value must say so,
                  // never silently close without saving.
                  final cleaned = controller.text
                      .toLowerCase()
                      .replaceAll(',', '')
                      .replaceAll(RegExp(r'₹|\$|rs\.?|inr|usd'), '')
                      .trim();
                  final v = double.tryParse(cleaned);
                  if (v == null || v <= 0) {
                    setDialogState(() => error = 'Enter a number, like 200');
                    return;
                  }
                  Navigator.pop(ctx, v);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (value != null && _agent != null) {
      await widget.repo.updateAgent(_agent!.copyWith(target: value));
      await widget.repo.logActivity(
        widget.agentId,
        'Target changed to $value',
        DateTime.now(),
      );
      _refresh();
    }
  }

  Future<void> _findSource() async {
    final agent = _agent;
    if (agent == null) return;
    final selected = await Navigator.of(context).push<ReviewedSource>(
      MaterialPageRoute(
        builder: (_) => SourceReviewScreen(
          task: agent.originalPrompt,
          discovery: widget.discovery ?? defaultSourceDiscovery(),
          fixedTarget: agent.target,
          fixedCondition: agent.condition,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final latest = await widget.repo.agentById(widget.agentId);
    if (!mounted || latest == null) return;
    await widget.repo.updateAgent(
      latest.copyWith(
        sourceUrl: selected.candidate.url.toString(),
        sourceIdentity: selected.identity,
        clearCurrentValue: true,
        consecutiveSourceBlocks: 0,
        nextCheckAt: DateTime.now(),
      ),
    );
    await widget.repo.logActivity(
      widget.agentId,
      'Confirmed matching source: ${selected.candidate.product} — ${selected.candidate.url}',
      DateTime.now(),
    );
    await _refresh();
  }

  Future<void> _setSourcePage() async {
    final controller = TextEditingController(text: _agent?.sourceUrl ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Source page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Page link',
            hintText: 'https://... (leave empty for manual values)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != null && _agent != null) {
      if (saved.isEmpty) {
        await widget.repo.updateAgent(_agent!.copyWith(clearSourceUrl: true));
        await widget.repo.logActivity(
          widget.agentId,
          'Source page cleared - values update manually',
          DateTime.now(),
        );
      } else {
        final url =
            GoalParser.extractUrl(saved) ??
            (saved.contains('.') && !saved.contains(' ')
                ? 'https://$saved'
                : null);
        final issue = url == null
            ? 'Enter a valid page link.'
            : PageValueFetcher.sourceIssue(url);
        if (issue != null) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(issue)));
          }
          return;
        }
        await widget.repo.updateAgent(
          _agent!.copyWith(
            sourceUrl: url!,
            clearSourceIdentity: true,
            consecutiveSourceBlocks: 0,
            nextCheckAt: DateTime.now(),
          ),
        );
        await widget.repo.logActivity(
          widget.agentId,
          'Source page set to $url',
          DateTime.now(),
        );
      }
      _refresh();
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete agent?'),
        content: const Text('This removes the agent and its activity history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.repo.deleteAgent(widget.agentId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _agent;
    return Scaffold(
      appBar: AppBar(title: Text(a?.title ?? 'Agent')),
      body: a == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Builder(
                  builder: (context) {
                    final running = a.status == AgentStatus.active;
                    final (bg, accent) = running
                        ? XColors.pastelFor(a.id ?? a.title.hashCode)
                        : (xPanel(context), XColors.inkSoft);
                    return Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(36),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: running
                                        ? accent
                                        : xTrack(context),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    a.statusLabel,
                                    overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: running
                                        ? Colors.white
                                        : xInkSoft(context),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              ),
                              const Spacer(),
                              Icon(
                                a.type == AgentType.reminder
                                    ? Icons.alarm_rounded
                                    : Icons.show_chart_rounded,
                                color: accent,
                              ),
                            ],
                          ),
                          if (a.type == AgentType.valueWatch &&
                              a.currentValue != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              a.currentValue! == a.currentValue!.roundToDouble()
                                  ? '${a.currentValue!.toInt()}'
                                  : '${a.currentValue}',
                              style: TextStyle(
                                fontSize: 52,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -2,
                                height: 1,
                                color: running ? accent : xInkSoft(context),
                              ),
                            ),
                          ] else
                            const SizedBox(height: 12),
                          const SizedBox(height: 6),
                          Text(
                            a.conditionLabel,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: running
                                        ? XColors.ink
                                        : xInk(context)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            a.typeLabel,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: running
                                        ? XColors.inkSoft
                                        : xInkSoft(context)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (a.needsSourceResolution) ...[
                  const SizedBox(height: 12),
                  Text(
                    a.isUnsupportedTicketWatch
                        ? 'Ticket-price monitoring is unavailable. The saved task and target are unchanged; no automatic checks will run.'
                        : 'This task is waiting for source resolution. No price has been checked. Empty checks will not repeat.',
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final r = await widget.checker.checkAgent(a);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                !r.evaluated
                                    ? 'Unable to check: ${r.summary}'
                                    : r.conditionMet
                                    ? 'Condition met - ${r.summary}'
                                    : 'Checked: ${r.summary}',
                              ),
                            ),
                          );
                          _refresh();
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Run now'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await widget.repo.updateAgent(
                            a.copyWith(
                              status: a.status == AgentStatus.paused
                                  ? AgentStatus.active
                                  : AgentStatus.paused,
                            ),
                          );
                          _refresh();
                        },
                        icon: Icon(
                          a.status == AgentStatus.paused
                              ? Icons.play_circle
                              : Icons.pause_circle,
                        ),
                        label: Text(
                          a.status == AgentStatus.paused ? 'Resume' : 'Pause',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                XToggleTile(
                  icon: a.notificationEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  title: 'Notifications',
                  subtitle: a.notificationEnabled
                      ? 'Notifying when the condition matches'
                      : 'Silent - checks still run',
                  bg: XColors.lemon,
                  accent: XColors.lemonDeep,
                  value: a.notificationEnabled,
                  onChanged: (v) async {
                    await widget.repo.updateAgent(
                      a.copyWith(notificationEnabled: v),
                    );
                    _refresh();
                  },
                ),
                const SizedBox(height: 12),
                if (!a.isUnsupportedTicketWatch &&
                    a.sourceUrl != null &&
                    PageValueFetcher.sourceIssue(a.sourceUrl!) != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        PageValueFetcher.sourceIssue(a.sourceUrl!)!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                if (a.type == AgentType.valueWatch)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Watch source',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            a.isUnsupportedTicketWatch
                                ? 'Ticket monitoring unavailable — saved task retained'
                                : a.sourceUrl ??
                                      'Manual value watch - no page linked',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            a.lastSuccessfulReadAt == null
                                ? 'Last successful read: none recorded'
                                : 'Last successful read: ${_fmtTime(a.lastSuccessfulReadAt!)}',
                          ),
                          if (a.lastSuccessfulReadAt != null) ...[
                            Text(
                              a.isTextWatch
                                  ? a.readingLabel(a.lastSuccessfulValue)
                                  : 'Value: ${a.lastSuccessfulValue ?? "Unknown"}',
                            ),
                            Text(
                              'Method: ${a.lastReadMethod ?? "Unknown (older version)"}',
                            ),
                            if (a.lastReadSourceUrl != null &&
                                a.lastReadSourceUrl!.isNotEmpty &&
                                a.lastReadSourceUrl != a.sourceUrl)
                              const Text(
                                'This read was from the previous source, not the current link.',
                              ),
                            if (a.lastReadMethod == 'Manual value entry')
                              const Text(
                                'User-entered value, not a live ticket price.',
                              ),
                            if (a.lastCheckedAt != null &&
                                a.lastCheckedAt!.isAfter(
                                  a.lastSuccessfulReadAt!,
                                ))
                              const Text(
                                'Latest check did not obtain a fresh page value. This is the last successful read.',
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'Watch setup',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                _row('Goal', a.originalPrompt),
                _row('Condition', a.conditionLabel),
                if (a.status == AgentStatus.active ||
                    a.status == AgentStatus.paused) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Check every',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in _intervalOptions)
                        ChoiceChip(
                          label: Text(_intervalChipLabel(d)),
                          selected: d == _selectedInterval,
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: d == _selectedInterval
                                ? Colors.white
                                : const Color(0xFF201A17),
                          ),
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : const Color(0xFFEFE9E1),
                          selectedColor: const Color(0xFF201A17),
                          onSelected: (_) =>
                              setState(() => _selectedInterval = d),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '5 and 10 minutes only while the app is open. Closed-app '
                    'background checks need at least 15 minutes on Android. '
                    'Changes apply to future checks.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          _savingInterval ||
                              _selectedInterval == null ||
                              _selectedInterval == a.checkInterval
                          ? null
                          : _saveInterval,
                      child: Text(
                        _savingInterval ? 'Saving…' : 'Save interval',
                      ),
                    ),
                  ),
                ] else
                  _row(
                    'Check interval',
                    'every ${a.checkInterval.inMinutes} min',
                  ),
                if (a.type == AgentType.valueWatch) ...[
                  _row('Current value', a.readingLabel(a.currentValue)),
                  _row('Previous value', a.readingLabel(a.previousValue)),
                  _row(
                    'Source page',
                    a.sourceUrl ?? 'Waiting for source discovery',
                  ),
                  const SizedBox(height: 4),
                ],
                const SizedBox(height: 16),
                Text(
                  'Timing',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _row('Created', _fmtTime(a.createdAt)),
                _row(
                  'Last checked',
                  a.lastCheckedAt == null
                      ? 'Never'
                      : _fmtTime(a.lastCheckedAt!),
                ),
                _row(
                  'Next check',
                  a.isUnsupportedTicketWatch
                      ? 'Not scheduled — ticket monitoring unavailable'
                      : a.sourceBlocked
                      ? 'Paused - source is blocking checks'
                      : a.needsSourceResolution
                      ? 'Waiting for a confirmed source'
                      : a.nextCheckAt == null
                      ? '-'
                      : 'Due from ${_fmtTime(a.nextCheckAt!)}',
                ),
                if (a.type == AgentType.valueWatch) ...[
                  const SizedBox(height: 4),
                  if (!a.isUnsupportedTicketWatch &&
                      a.sourceUrl != null &&
                      PageValueFetcher.bookMyShowApiUrl(a.sourceUrl!) != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.public),
                      label: const Text('Check in browser (manual)'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final outcome = await BrowserPriceCheck.read(
                          a.sourceUrl!,
                        );
                        final latest = await widget.repo.agentById(
                          widget.agentId,
                        );
                        if (!mounted ||
                            latest == null ||
                            latest.status != AgentStatus.active ||
                            latest.sourceUrl != a.sourceUrl) {
                          return;
                        }
                        final checker = AgentChecker(
                          repo: widget.repo,
                          notifier: widget.checker.notifier,
                          fetcher: (_) async => outcome,
                          readMethod: 'Browser read (user started)',
                        );
                        final result = await checker.checkAgent(latest);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text(result.summary)),
                        );
                        await _refresh();
                      },
                    ),
                  const SizedBox(height: 16),
                  if (a.sourceBlocked) ...[
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'This source is blocking automated checks, so automatic checks are paused. Set a different source page to resume - history is kept.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Adjust this watch',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _findSource,
                    icon: const Icon(Icons.search),
                    label: Text(
                      a.isUnsupportedTicketWatch
                          ? 'View ticket-check limits'
                          : a.needsSourceResolution
                          ? 'Find matching source'
                          : 'Find a different source',
                    ),
                  ),
                  if (!a.isTextWatch && !a.isUnsupportedTicketWatch)
                    OutlinedButton.icon(
                      onPressed: _updateValue,
                      icon: const Icon(Icons.edit),
                      label: const Text('Update current value'),
                    ),
                  if (!a.isTextWatch)
                    OutlinedButton.icon(
                      onPressed: _editTarget,
                      icon: const Icon(Icons.adjust),
                      label: const Text('Edit target'),
                    ),
                  if (!a.isTextWatch && !a.isUnsupportedTicketWatch)
                    OutlinedButton.icon(
                      onPressed: _setSourcePage,
                      icon: const Icon(Icons.link),
                      label: const Text('Set source page'),
                    ),
                ],
                const SizedBox(height: 16),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _delete,
                  icon: Icon(
                    Icons.delete,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  label: Text(
                    'Delete',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'This task’s activity history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ActivityScreen(
                        repo: widget.repo,
                        agentId: widget.agentId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('Open task history'),
                ),
                const SizedBox(height: 8),
                if (_activity.isEmpty)
                  const Text('No activity yet. Run a check to see the log.')
                else
                  ...groupHistoryCycles(_activity).map(
                    (cycle) => CycleCard(cycle: cycle),
                  ),
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: () => Clipboard.setData(ClipboardData(text: value)),
              child: Text(value, style: const TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtTime(DateTime t) => fmtAppTime(t);
}
