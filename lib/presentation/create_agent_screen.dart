import 'package:flutter/material.dart';

import '../data/agent_repository.dart';
import '../domain/agent.dart';
import '../domain/parser.dart';

class CreateAgentScreen extends StatefulWidget {
  final AgentRepository repo;
  const CreateAgentScreen({super.key, required this.repo});

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
  ParsedGoal? _parsed;
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
    if (p == null || p.outcome != ParseOutcome.ok) return;
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
      ),
    );
    if (mounted) Navigator.of(context).pop();
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide =
                      constraints.maxWidth >= 330 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3;
                  final cards = [
                    _ExampleTile(
                      icon: Icons.show_chart_rounded,
                      title: 'Watch a value',
                      subtitle: 'Below a target',
                      onTap: () => _controller.text = suggestions[0],
                    ),
                    _ExampleTile(
                      icon: Icons.alarm_rounded,
                      title: 'Set a reminder',
                      subtitle: 'At the right time',
                      onTap: () => _controller.text = suggestions[2],
                    ),
                  ];
                  return wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 10),
                            Expanded(child: cards[1]),
                          ],
                        )
                      : Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 10),
                            cards[1],
                          ],
                        );
                },
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
                '2  Source page',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Optional for value watches. You can also enter values manually.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Page link',
                  hintText: 'https://...',
                  prefixIcon: Icon(Icons.link_rounded),
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
                      'I could not turn that into a check yet. Try a price target ("cheaper than ₹50,000") or a reminder ("remind me in 2 hours").',
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
                            'Condition: ${p.condition == WatchCondition.lessThan ? 'below' : 'above'} ${p.target}',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _sourceUrl != null
                                ? 'Lookout fetches the current value from that page on every check.'
                                : 'Add a page link above, or update the value manually on the agent page.',
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
                            DropdownButton<Duration>(
                              value: _interval,
                              items: [
                                for (final d in _intervals)
                                  DropdownMenuItem(
                                    value: d,
                                    child: Text(_intervalLabel(d)),
                                  ),
                              ],
                              onChanged: (d) => setState(() => _interval = d!),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create Agent'),
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
                child: ActionChip(
                  avatar: const Icon(Icons.info_outline_rounded, size: 16),
                  label: const Text('Webpage-change checks'),
                  onPressed: () => _controller.text = suggestions[1],
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
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
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
    );
  }
}
