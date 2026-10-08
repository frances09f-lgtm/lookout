import 'package:flutter/material.dart';

import '../data/agent_repository.dart';
import '../domain/agent.dart';
import '../domain/parser.dart';
import '../services/gold_quote.dart';
import '../services/source_discovery.dart';

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

  Future<void> findSource() async {
    String? retailer;
    if (!SourceDiscovery.movie(_controller.text))
      retailer = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Find a product source'),
          children: [
            for (final name in ['Flipkart', 'Amazon'])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, name),
                child: Text(name),
              ),
          ],
        ),
      );
    if (!SourceDiscovery.movie(_controller.text) && retailer == null) return;
    try {
      final url = await SourceDiscovery.pick(
        _controller.text,
        retailer: retailer,
      );
      if (url != null && mounted) setState(() => _urlController.text = url);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Source selection not completed. Choose an exact page or keep a manual watch.',
            ),
          ),
        );
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Create Agent')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'What do you want me to watch?',
            ),
          ),
          const SizedBox(height: 12),
          if (!GoldQuote.isGold(_controller.text))
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Page link to fetch the value from (optional)',
                hintText: 'https://...',
              ),
            ),
          if (_parsed?.type == AgentType.valueWatch &&
              !GoldQuote.isGold(_controller.text))
            OutlinedButton.icon(
              onPressed: findSource,
              icon: const Icon(Icons.search),
              label: Text(
                SourceDiscovery.movie(_controller.text)
                    ? 'Find cinema / show source'
                    : 'Find product source',
              ),
            ),
          if (_parsed?.type == AgentType.valueWatch &&
              !GoldQuote.isGold(_controller.text))
            const Text(
              'No link to paste: open a known source and confirm the exact product or dated show. Site blocks may still prevent background price reads.',
              style: TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in suggestions)
                ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  onPressed: () => _controller.text = s,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (p != null && p.outcome == ParseOutcome.needsV2)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(p.note ?? ''),
              ),
            ),
          if (p != null && p.outcome == ParseOutcome.unclear)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'I could not turn that into a check yet. Try a price target ("cheaper than ₹50,000") or a reminder ("remind me in 2 hours").',
                ),
              ),
            ),
          if (p != null && p.outcome == ParseOutcome.ok) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'I will create this agent:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Type: ${p.type == AgentType.reminder ? 'Reminder' : 'Value watch'}',
                    ),
                    Text('Title: ${p.title}'),
                    if (p.type == AgentType.reminder)
                      Text(
                        'Fires: ${DateTime.fromMillisecondsSinceEpoch(p.target!.round())}',
                      ),
                    if (p.type == AgentType.valueWatch)
                      Text(
                        'Parsed threshold: ${p.condition == WatchCondition.lessThan ? 'below' : 'above'} ${p.target}',
                      ),
                    if (p.type == AgentType.valueWatch)
                      Text(
                        GoldQuote.isGold(_controller.text)
                            ? 'Gold uses Swissquote XAU/USD mid in USD per oz, the same quote source as Sona. Checks require a quote no older than 5 minutes.'
                            : _sourceUrl != null
                            ? 'Lookout fetches the current value from that page on every check.'
                            : 'No source selected - use Find source above without copying a link, or update the value manually. Source selection does not guarantee the site permits background price reads.',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Check every'),
                const SizedBox(width: 12),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.check),
              label: const Text('Create Agent'),
            ),
          ],
        ],
      ),
    );
  }
}
