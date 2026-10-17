import 'press_feedback.dart';

import 'package:flutter/material.dart';

import '../services/source_discovery.dart';
import '../domain/agent.dart';
import '../domain/ticket_task.dart';

/// Foreground clarification and explicit source review; never activates a watch.
class SourceReviewScreen extends StatefulWidget {
  final String task;
  final SourceDiscoveryService discovery;
  final double? fixedTarget;
  final WatchCondition? fixedCondition;
  const SourceReviewScreen({
    super.key,
    required this.task,
    required this.discovery,
    this.fixedTarget,
    this.fixedCondition,
  });
  @override
  State<SourceReviewScreen> createState() => _SourceReviewScreenState();
}

class _SourceReviewScreenState extends State<SourceReviewScreen> {
  late final TextEditingController _task;
  String? _country;
  String? _currency;
  DiscoveryResult? _result;
  List<String> _questions = const [];
  SourceCandidate? _selected;
  DiscoverySpec? _spec;
  bool _busy = false;
  bool get _textTask =>
      DiscoveryTaskParser.parse(_task.text).spec?.isText ?? false;
  int _revision = 0;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _task = TextEditingController(text: widget.task);
    _task.addListener(_invalidate);
  }

  void _invalidate() {
    setState(() {
      _revision++;
      _selected = null;
      _result = null;
      _questions = const [];
      _busy = false;
    });
  }

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final parsed = DiscoveryTaskParser.parse(
      _task.text,
      country: _country,
      currency: _currency,
    );
    setState(() {
      _questions = parsed.questions;
      _result = null;
      _selected = null;
    });
    if (parsed.spec == null) return;
    final originalText =
        DiscoveryTaskParser.parse(widget.task).spec?.isText ?? false;
    if (parsed.spec!.isText != originalText) {
      setState(
        () => _questions = [
          'The check type changed. Go back and edit the task before choosing a source.',
        ],
      );
      return;
    }
    if (originalText &&
        DiscoveryTaskParser.parse(widget.task).spec?.phrase !=
            parsed.spec!.phrase) {
      setState(
        () => _questions = [
          'Go back to edit the watched phrase before choosing a source.',
        ],
      );
      return;
    }
    _spec = parsed.spec;
    final revision = _revision;
    final request = ++_request;
    setState(() => _busy = true);
    final result = await widget.discovery.discover(parsed.spec!);
    if (!mounted || revision != _revision || request != _request) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  Future<void> _useSource() async {
    final selected = _selected;
    final spec = _spec;
    if (selected == null || spec == null || _busy) return;
    final revision = _revision;
    final request = ++_request;
    setState(() => _busy = true);
    final fresh = await widget.discovery.revalidate(spec, selected);
    if (!mounted || revision != _revision || request != _request) return;
    if (fresh == null) {
      setState(() {
        _busy = false;
        _selected = null;
        _result = null;
        _questions = [
          'The source changed, expired or could not be verified. Find matching pages again; no watch was started.',
        ];
      });
      return;
    }
    Navigator.pop(
      context,
      ReviewedSource(
        DiscoverySpec(
          model: spec.model,
          kind: spec.kind,
          phrase: spec.phrase,
          storageGb: spec.storageGb,
          target: widget.fixedTarget ?? spec.target,
          condition: widget.fixedCondition ?? spec.condition,
          country: spec.country,
          currency: spec.currency,
          colour: spec.colour,
        ),
        fresh,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (TicketTaskPolicy.isPriceTask(widget.task)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket price check')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              TicketTaskPolicy.title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text('Your saved task'),
            const SizedBox(height: 8),
            SelectableText(widget.task),
            if (widget.fixedTarget != null) ...[
              const SizedBox(height: 12),
              Text(
                'Saved target: strictly ${widget.fixedCondition == WatchCondition.greaterThan ? 'above' : 'below'} ${widget.fixedTarget!.toStringAsFixed(widget.fixedTarget! == widget.fixedTarget!.roundToDouble() ? 0 : 2)}. Unchanged.',
              ),
            ],
            const SizedBox(height: 16),
            const Text(TicketTaskPolicy.limitation),
            const SizedBox(height: 16),
            const Text(TicketTaskPolicy.requirements),
            const SizedBox(height: 16),
            const Text(TicketTaskPolicy.transport),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Back to task'),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Find a source')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'A task, not a link.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose an exact product price or literal text on a public page. Review the actual source before activation. Free-form judgements and private pages are not supported.',
          ),
          if (widget.fixedTarget != null && !_textTask)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Clarify product details below. The saved target stays ${widget.fixedCondition == WatchCondition.greaterThan ? 'above' : 'below'} ${widget.fixedTarget}.',
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _task,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Your task',
              hintText: 'Check Sony WH-1000XM5 price below 25000',
            ),
          ),
          const SizedBox(height: 12),
          if (!_textTask)
            LookoutPressFeedback(
              child: DropdownButtonFormField<String>(
                initialValue: _country,
                decoration: const InputDecoration(
                  labelText: 'Shopping country',
                ),
                items: const [
                  DropdownMenuItem(value: 'IN', child: Text('India')),
                  DropdownMenuItem(value: 'US', child: Text('United States')),
                ],
                onChanged: (v) {
                  _country = v;
                  _invalidate();
                },
              ),
            ),
          const SizedBox(height: 12),
          if (!_textTask)
            LookoutPressFeedback(
              child: DropdownButtonFormField<String>(
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'Price currency'),
                items: const [
                  DropdownMenuItem(value: 'INR', child: Text('INR — ₹')),
                  DropdownMenuItem(value: 'USD', child: Text('USD — \$')),
                ],
                onChanged: (v) {
                  _currency = v;
                  _invalidate();
                },
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Search sends the product or page subject to Tavily’s free, rate-limited service. The target price or watched phrase is not sent. Lookout then reads public HTML directly; search snippets are never check evidence.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _find,
            icon: Icon(_busy ? Icons.hourglass_empty : Icons.search),
            label: Text(
              _busy ? 'Finding matching pages…' : 'Find matching pages',
            ),
          ),
          for (final q in _questions)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(q)),
          if (_result?.issue != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_result!.issue!),
            ),
          if (_result != null && _result!.candidates.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Review the match',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _spec?.isText == true
                  ? 'Watch for “${_spec!.phrase}” on this page only. This checks literal text—not whether a result is official or a ticket is bookable.'
                  : 'Read once now; future access or stock can change. Exact item prices, not guaranteed delivery-inclusive totals.',
            ),
            for (final item in _result!.candidates)
              Card(
                color: _selected == item ? c.primaryContainer : null,
                child: LookoutPressFeedback(
                  child: ListTile(
                    title: Text(item.product),
                    subtitle: Text(
                      '${item.readingLabel}\n${item.url}\nRead ${item.checkedAt.toLocal()}',
                    ),
                    isThreeLine: true,
                    trailing: Icon(
                      _selected == item
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: () => setState(() => _selected = item),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _selected == null || _busy ? null : _useSource,
              child: const Text('Use this source'),
            ),
          ],
          if (_result != null && _result!.reviewOnly.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Pages needing more evidence',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Review only — unable to monitor. Choosing a country does not verify the seller’s market or select an offer.',
            ),
            for (final page in _result!.reviewOnly)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.product,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(page.url.toString()),
                      const SizedBox(height: 12),
                      const Text('Missing or conflicting evidence'),
                      for (final blocker in page.blockers)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(blocker),
                        ),
                      const SizedBox(height: 12),
                      if (page.reportedOffers.isNotEmpty)
                        const Text(
                          'Page-reported offers — not verified prices',
                        ),
                      for (final offer in page.reportedOffers)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(offer),
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Lookout needs one exact in-stock offer and a verified market before it can monitor this page. Try another search.',
                      ),
                      const SizedBox(height: 12),
                      const FilledButton(
                        onPressed: null,
                        child: Text('Unable to monitor'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.maybePop(context),
            child: Text(
              _textTask
                  ? 'Back to edit task'
                  : 'Use a manual page link instead',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _textTask
                ? 'No watch starts until you review a matching page. Blocked or unreadable pages stay unknown, not phrase absent.'
                : 'No watch starts until you review a matching page. Product checks need an in-stock offer. Unreadable pages stay unknown; a manual link is an optional fallback.',
          ),
        ],
      ),
    );
  }
}
