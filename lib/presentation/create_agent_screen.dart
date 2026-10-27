import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/agent_repository.dart';
import '../domain/agent.dart';
import '../domain/parser.dart';
import '../domain/ticket_task.dart';
import 'expressive.dart';
import 'press_feedback.dart';
import 'source_review_screen.dart';
import '../services/page_fetch.dart';
import '../services/source_discovery.dart';

class CreateAgentScreen extends StatefulWidget {
  final AgentRepository repo;
  final SourceDiscoveryService? discovery;
  const CreateAgentScreen({super.key, required this.repo, this.discovery});

  @override
  State<CreateAgentScreen> createState() => _CreateAgentScreenState();
}

enum _EntryMode { boxes, describe }

class _CreateAgentScreenState extends State<CreateAgentScreen> {
  static const suggestions = [
    'Tell me when this product becomes cheaper than ₹50,000',
    'Tell me when this webpage changes',
    'Remind me in 2 hours if this task hasn\'t been completed',
  ];

  final _controller = TextEditingController();
  final _urlController = TextEditingController();
  final _productController = TextEditingController();
  final _targetController = TextEditingController();
  _EntryMode _mode = _EntryMode.boxes;
  bool _dropsBelow = true;
  String _unit = '₹';
  bool _testingLink = false;
  bool _boxesReviewShown = false;
  FetchOutcome? _testOutcome;
  String? _testedUrl;
  String? _lastAutoUrl;
  String? _lastTaskText;
  ParsedGoal? _parsed;
  ReviewedSource? _reviewed;
  bool _creating = false;
  bool get _isText =>
      DiscoveryTaskParser.parse(_controller.text).spec?.isText ?? false;
  bool get _isTicket => TicketTaskPolicy.isPriceTask(_controller.text);
  Duration _interval = const Duration(hours: 1);

  static const _intervals = [
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
    _productController.addListener(_composeFromBoxes);
    _targetController.addListener(_composeFromBoxes);
  }

  /// The boxes are structured editors over the same task text the free-text
  /// flow produces, so parsing, review and creation behave identically.
  void _composeFromBoxes() {
    if (_mode != _EntryMode.boxes) return;
    final prod = _productController.text.trim();
    final tgt = _targetController.text.trim();
    final text = (prod.isEmpty || tgt.isEmpty)
        ? ''
        : 'Tell me when $prod ${_dropsBelow ? 'drops below' : 'rises above'} $_unit$tgt';
    if (text != _controller.text) {
      _boxesReviewShown = false;
      _controller.text = text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _urlController.dispose();
    _productController.dispose();
    _targetController.dispose();
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

  Future<void> _testLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testingLink = true;
      _testOutcome = null;
      _testedUrl = null;
    });
    final FetchOutcome outcome;
    // Amazon pages run through the same EMI-safe path as background checks:
    // only the buy-box price blocks count, so an EMI amount can no longer
    // come back as the verified price.
    final fetch =
        PageValueFetcher.debugFetchValue ?? PageValueFetcher.fetchValue;
    outcome = await fetch(url);
    if (!mounted || _urlController.text.trim() != url) return;
    setState(() {
      _testingLink = false;
      _testOutcome = outcome;
      _testedUrl = url;
    });
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
              if (_mode == _EntryMode.boxes) ..._buildBoxes(theme, colors, p),
              if (_mode == _EntryMode.describe) ..._buildDescribe(theme, colors),
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
              if (p != null &&
                  p.outcome == ParseOutcome.ok &&
                  (_mode == _EntryMode.describe || _boxesReviewShown)) ...[
                Text(
                  _mode == _EntryMode.boxes ? 'Review & schedule' : '3  Review & schedule',
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
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('Check every'),
                            for (final d in _intervals)
                              LookoutPressFeedback(
                                child: ActionChip(
                                  label: Text(_intervalLabel(d)),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: d == _interval
                                        ? Colors.white
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  backgroundColor: d == _interval
                                      ? const Color(0xFF201A17)
                                      : Colors.white,
                                  onPressed: () =>
                                      setState(() => _interval = d),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '5 and 10 minutes only while the app is open. '
                          'Closed-app background checks need at least 15 '
                          'minutes on Android.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
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
                        ? (_mode == _EntryMode.boxes
                              ? 'Review watch'
                              : 'Find matching source')
                        : 'Create Agent',
                  ),
                ),
              ],
              if (_mode == _EntryMode.describe) ...[
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
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBoxes(ThemeData theme, ColorScheme colors, ParsedGoal? p) {
    final ready = p != null && p.outcome == ParseOutcome.ok;
    // Approved green primary CTA (mockup): deep green, white label.
    final ctaGreen = theme.brightness == Brightness.dark
        ? const Color(0xFF2E5B46)
        : XColors.mintDeep;
    return [
      Text(
        'Watch a price,\nin three boxes.',
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -.8,
          height: 1.15,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Name it, set your target, paste the link. Review it before you create it.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 24),
      _boxLabel(theme, colors, 'PRODUCT'),
      const SizedBox(height: 8),
      TextField(
        controller: _productController,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'What are you watching? e.g. boAt Airdopes 141',
        ),
      ),
      const SizedBox(height: 18),
      _boxLabel(theme, colors, 'TARGET'),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final field = TextField(
            controller: _targetController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₹\$]')),
            ],
            decoration: const InputDecoration(hintText: '1,299'),
          );
          final unit = DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _unit,
              isDense: true,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              items: const [
                DropdownMenuItem(value: '₹', child: Text('₹')),
                DropdownMenuItem(value: '\$', child: Text('\$')),
              ],
              onChanged: (v) => setState(() {
                _unit = v ?? '₹';
                _composeFromBoxes();
              }),
            ),
          );
          final chip = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ctaGreen,
              borderRadius: BorderRadius.circular(999),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<bool>(
                  value: _dropsBelow,
                  isDense: true,
                  dropdownColor: ctaGreen,
                  iconEnabledColor: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Drops below')),
                    DropdownMenuItem(value: false, child: Text('Rises above')),
                  ],
                  onChanged: (v) => setState(() {
                    _dropsBelow = v ?? true;
                    _composeFromBoxes();
                  }),
                ),
              ),
            ),
          );
          // scaleDown keeps the unit + condition pair inside narrow screens
          // and large text scales without changing its normal-size look.
          final controls = FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [unit, const SizedBox(width: 8), chip],
            ),
          );
          // Wide enough for value, unit and condition on one compact row.
          // Measure in text-scaled pixels so large font scales stack instead
          // of clipping.
          final effectiveWidth =
              constraints.maxWidth / MediaQuery.textScalerOf(context).scale(1);
          if (effectiveWidth >= 300) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: field),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: controls,
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [field, const SizedBox(height: 10), controls],
          );
        },
      ),
      const SizedBox(height: 6),
      Text(
        _dropsBelow
            ? 'Alert me when the value drops below this.'
            : 'Alert me when the value rises above this.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 18),
      _boxLabel(theme, colors, 'LINK'),
      const SizedBox(height: 8),
      TextField(
        controller: _urlController,
        keyboardType: TextInputType.url,
        onChanged: (_) => setState(() {
          _reviewed = null;
          _testOutcome = null;
          _testedUrl = null;
          _boxesReviewShown = false;
        }),
        decoration: const InputDecoration(
          hintText: 'Paste the product page link',
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'Lookout reads the price from this page on every check.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: (_sourceUrl == null || _testingLink) ? null : _testLink,
          icon: _testingLink
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_circle_outline_rounded, size: 18),
          label: Text(_testingLink ? 'Reading the page…' : 'Test link'),
        ),
      ),
      if (_testOutcome != null && _testedUrl == _urlController.text.trim())
        Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_testOutcome!.ok) ...[
                  Text(
                    'Read ${_testOutcome!.value}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  _testOutcome!.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (_testOutcome!.ok) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Read once just now; future reads may fail. Check the number matches the price on the page.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      if (_reviewed != null) ...[
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
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
      ],
      const SizedBox(height: 24),
      if (!ready || !_boxesReviewShown)
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: ready
                ? () => setState(() => _boxesReviewShown = true)
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: ctaGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: ctaGreen.withValues(alpha: 0.45),
              disabledForegroundColor: Colors.white70,
            ),
            child: const Text('Review watch'),
          ),
        ),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: () => setState(() => _mode = _EntryMode.describe),
          child: const Text('Set a reminder or watch text on a page instead'),
        ),
      ),
    ];
  }

  Widget _boxLabel(ThemeData theme, ColorScheme colors, String text) => Text(
    text,
    style: theme.textTheme.labelSmall?.copyWith(
      color: colors.primary,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w700,
    ),
  );

  List<Widget> _buildDescribe(ThemeData theme, ColorScheme colors) => [
    SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: () => setState(() => _mode = _EntryMode.boxes),
        child: const Row(
          children: [
            Icon(Icons.grid_view_rounded, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Watch a price with boxes instead')),
          ],
        ),
      ),
    ),
    const SizedBox(height: 4),
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
      style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
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
      onPressed: () => _controller.text =
          'Check University results page contains "Results published"',
      icon: const Icon(Icons.text_snippet_outlined),
      label: const Text('Watch for text on a public page'),
    ),
    const SizedBox(height: 24),
    Text(
      '1  What to watch',
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 6),
    Text(
      'Just describe your task. Lookout supports exact product prices and literal text on public pages. It asks for missing details, then finds pages for you to review—not every kind of task yet.',
      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
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
  ];
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
