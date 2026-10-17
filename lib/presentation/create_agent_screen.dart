import 'package:flutter/material.dart';

import '../data/agent_repository.dart';
import '../domain/agent.dart';
import '../domain/parser.dart';
import '../domain/ticket_task.dart';
import 'press_feedback.dart';
import 'source_review_screen.dart';
import '../services/source_discovery.dart';

class CreateAgentScreen extends StatefulWidget {
  final AgentRepository repo;
  final SourceDiscoveryService? discovery;
  const CreateAgentScreen({super.key, required this.repo, this.discovery});

  @override
  State<CreateAgentScreen> createState() => _CreateAgentScreenState();
}

class _CreateAgentScreenState extends State<CreateAgentScreen> {
  static const suggestions = [
    'Tell me when this product becomes cheaper than ₹50,000',
    'Tell me when this webpage changes',
    'Remind me in 2 hours if this task hasn\'t been completed',
  ];

  final _controller = TextEditingController();
  final _urlController = TextEditingController();
  String? _lastAutoUrl;
  String? _lastTaskText;
  ParsedGoal? _parsed;
  ReviewedSource? _reviewed;
  bool _creating = false;
  bool get _isText =>
      DiscoveryTaskParser.parse(_controller.text).spec?.isText ?? false;
  bool get _isTicket => TicketTaskPolicy.isPriceTask(_controller.text);
  Duration _interval = const Duration(minutes: 30);

  static const _intervals = [
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 3),
    Duration(hours: 6),
    Duration(hours: 12),
    Duration(hours: 24),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(
      () => setState(() {
        final text = _controller.text.trim();
        if (text == _lastTaskText) return;
        _lastTaskText = text;
        if (_reviewed != null) {
          _reviewed = null;
          _urlController.clear();
        }
        _parsed = text.isEmpty ? null : GoalParser.parse(text);
        final u = _parsed?.sourceUrl;
        if (u != null && u != _lastAutoUrl) {
          _urlController.text = u;
          _lastAutoUrl = u;
        }
      }),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String? get _sourceUrl {
    final typed = _urlController.text.trim();
    if (typed.isEmpty) return null;
    return GoalParser.extractUrl(typed) ??
        (typed.contains('.') && !typed.contains(' ') ? 'https://$typed' : null);
  }

  String _intervalLabel(Duration d) => d.inMinutes < 60
      ? '${d.inMinutes} min'
      : d.inHours < 24
      ? '${d.inHours} h'
      : '${d.inDays} day';

  Future<void> _create() async {
    final p = _parsed;
    if (p == null || p.outcome != ParseOutcome.ok || _creating) return;
    if (p.type == AgentType.valueWatch &&
        (_isTicket || _sourceUrl == null || (_isText && _reviewed == null))) {
      final reviewed = await Navigator.of(context).push<ReviewedSource>(
        MaterialPageRoute(
          builder: (_) => SourceReviewScreen(
            task: _controller.text,
            discovery: widget.discovery ?? defaultSourceDiscovery(),
            fixedTarget: p.target,
            fixedCondition: p.condition,
          ),
        ),
      );
      if (!mounted || reviewed == null) return;
      setState(() {
        _reviewed = reviewed;
        _urlController.text = reviewed.candidate.url.toString();
      });
      return; // source review never silently creates or activates a watch
    }
    setState(() => _creating = true);
    try {
      final reviewed = _reviewed;
      if (reviewed != null) {
        final task = _controller.text;
        final url = _sourceUrl;
        final fresh = await (widget.discovery ?? defaultSourceDiscovery())
            .revalidate(reviewed.spec, reviewed.candidate);
        if (!mounted ||
            _reviewed != reviewed ||
            _controller.text != task ||
            _sourceUrl != url) {
          return;
        }
        if (fresh == null) {
          setState(() {
            _reviewed = null;
            _urlController.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The reviewed source changed, expired or could not be verified. Find and review it again; no watch was created.',
              ),
            ),
          );
          return;
        }
      }
      await widget.repo.insertAgent(
        Agent(
          title: p.title,
          originalPrompt: _controller.text.trim(),
          type: p.type!,
          status: AgentStatus.active,
          createdAt: DateTime.now(),
          nextCheckAt: DateTime.now(),
          checkInterval: _interval,
          condition: p.condition!,
          target: p.target!,
          sourceUrl: _sourceUrl,
          sourceIdentity: _reviewed?.identity,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _parsed;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create Agent')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            children: [
              Text(
                'One less thing\nto keep checking.',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Describe a target or set a reminder. Review it before you create it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'START WITH AN EXAMPLE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ExampleTile(
                      icon: Icons.show_chart_rounded,
                      title: 'Watch a value',
                      subtitle: 'Below a target',
                      onTap: () => _controller.text = suggestions[0],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ExampleTile(
                      icon: Icons.alarm_rounded,
                      title: 'Set a reminder',
                      subtitle: 'At the right time',
                      onTap: () => _controller.text = suggestions[2],
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => _controller.text = 'Check University results page contains "Results published"',
                icon: const Icon(Icons.text_snippet_outlined),
                label: const Text('Watch for text on a public page'),
              ),
              const SizedBox(height: 24),
              Text(
                '1  What to watch',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'What do you want me to watch?',
                  hintText: 'Tell me when this becomes cheaper than 500',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                '2  Find a source',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Just describe your task. Lookout supports exact product prices and literal text on public pages. It asks for missing details, then finds pages for you to review—not every kind of task yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              if (_reviewed != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Reviewed source'),
                        Text(_reviewed!.candidate.product),
                        Text(_reviewed!.candidate.url.toString()),
                        Text(
                          '${_reviewed!.candidate.readingLabel} · read once; future reads may fail',
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_isText && !_isTicket)
                LookoutPressFeedback(
                  child: ExpansionTile(
                    title: const Text('Advanced: optional page link'),
                    children: [
                      TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        onChanged: (_) => setState(() => _reviewed = null),
                        decoration: const InputDecoration(
                          labelText: 'Page link',
                          hintText: 'https://...',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              if (p != null && p.outcome == ParseOutcome.needsV2)
                Card(
                  color: colors.tertiaryContainer,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(p.note ?? ''),
                  ),
                ),
              if (p != null && p.outcome == ParseOutcome.unclear)
                const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'I could not turn that into a check yet. Try an exact product price, a reminder, or: check University results page contains "Results published". Semantic judgements, arbitrary numeric metrics, availability and webpage-change checks need a dedicated evaluator and cannot start yet.',
                    ),
                  ),
                ),
              if (p != null && p.outcome == ParseOutcome.ok) ...[
                Text(
                  '3  Review & schedule',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.type == AgentType.reminder
                              ? 'Reminder'
                              : _isTicket
                              ? 'Ticket price check — unavailable'
                              : _isText
                              ? 'Page text watch'
                              : 'Value watch',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          p.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (p.type == AgentType.reminder)
                          Text(
                            'Fires: ${DateTime.fromMillisecondsSinceEpoch(p.target!.round())}',
                          ),
                        if (p.type == AgentType.valueWatch) ...[
                          Text(
                            _isText
                                ? 'Condition: reviewed page contains “${DiscoveryTaskParser.parse(_controller.text).spec!.phrase}”'
                                : 'Condition: ${p.condition == WatchCondition.lessThan ? 'below' : 'above'} ${p.target}',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isTicket
                                ? TicketTaskPolicy.limitation
                                : _sourceUrl != null
                                ? (_isText
                                      ? 'Each check re-reads this page. Exact text only, not a judgement about what happened.'
                                      : 'Lookout fetches the current value from that page on every check.')
                                : 'Find and review a matching source before starting this watch. No URL required.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Check every'),
                            LookoutPressFeedback(
                              child: DropdownButton<Duration>(
                                value: _interval,
                                items: [
                                  for (final d in _intervals)
                                    DropdownMenuItem(
                                      value: d,
                                      child: Text(_intervalLabel(d)),
                                    ),
                                ],
                                onChanged: (d) =>
                                    setState(() => _interval = d!),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _creating ? null : _create,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(
                    _creating
                        ? 'Creating…'
                        : _isTicket
                        ? 'View ticket-check limits'
                        : p.type == AgentType.valueWatch &&
                              (_sourceUrl == null ||
                                  (_isText && _reviewed == null))
                        ? 'Find matching source'
                        : 'Create Agent',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Not available yet',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: LookoutPressFeedback(
                  child: ActionChip(
                    avatar: const Icon(Icons.info_outline_rounded, size: 16),
                    label: const Text('Webpage-change checks'),
                    onPressed: () => _controller.text = suggestions[1],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExampleTile extends StatelessWidget {
  const _ExampleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: LookoutPressFeedback(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 84),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
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
