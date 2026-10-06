import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/agent_repository.dart';
import '../domain/activity.dart';
import '../domain/agent.dart';
import '../services/checker.dart';

class AgentDetailsScreen extends StatefulWidget {
  final AgentRepository repo;
  final AgentChecker checker;
  final int agentId;

  const AgentDetailsScreen(
      {super.key,
      required this.repo,
      required this.checker,
      required this.agentId});

  @override
  State<AgentDetailsScreen> createState() => _AgentDetailsScreenState();
}

class _AgentDetailsScreenState extends State<AgentDetailsScreen> {
  Agent? _agent;
  List<ActivityEntry> _activity = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final a = await widget.repo.agentById(widget.agentId);
    if (a == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final log = await widget.repo.activityFor(widget.agentId);
    if (mounted) {
      setState(() {
        _agent = a;
        _activity = log;
      });
    }
  }

  Future<void> _updateValue() async {
    final controller = TextEditingController(
        text: _agent?.currentValue?.toString() ?? '');
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(controller.text.replaceAll(',', ''))),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null && _agent != null) {
      await widget.repo.updateAgent(_agent!.copyWith(
          previousValue: _agent!.currentValue, currentValue: value));
      await widget.repo
          .logActivity(widget.agentId, 'Value updated to $value', DateTime.now());
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
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
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
                Wrap(spacing: 8, children: [
                  Chip(label: Text(a.typeLabel), avatar: const Icon(Icons.tag, size: 16)),
                  Chip(label: Text(a.statusLabel)),
                  Chip(
                    avatar: Icon(
                        a.notificationEnabled
                            ? Icons.notifications_active
                            : Icons.notifications_off,
                        size: 16),
                    label: Text(
                        a.notificationEnabled ? 'Notifying' : 'Silent'),
                  ),
                ]),
                const SizedBox(height: 12),
                _row('Goal', a.originalPrompt),
                _row('Condition', a.conditionLabel),
                _row('Check interval', 'every ${a.checkInterval.inMinutes} min'),
                _row('Created', _fmtTime(a.createdAt)),
                _row('Last checked',
                    a.lastCheckedAt == null ? 'Never' : _fmtTime(a.lastCheckedAt!)),
                _row('Next check',
                    a.nextCheckAt == null ? '-' : _fmtTime(a.nextCheckAt!)),
                if (a.type == AgentType.valueWatch) ...[
                  _row('Current value', a.currentValue?.toString() ?? 'Not set'),
                  _row('Previous value', a.previousValue?.toString() ?? '-'),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _updateValue,
                    icon: const Icon(Icons.edit),
                    label: const Text('Update current value'),
                  ),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final r = await widget.checker.checkAgent(a);
                        messenger.showSnackBar(SnackBar(
                            content: Text(r.conditionMet
                                ? 'Condition met - ${r.summary}'
                                : 'Checked: ${r.summary}')));
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
                        await widget.repo.updateAgent(a.copyWith(
                            status: a.status == AgentStatus.paused
                                ? AgentStatus.active
                                : AgentStatus.paused));
                        _refresh();
                      },
                      icon: Icon(a.status == AgentStatus.paused
                          ? Icons.play_circle
                          : Icons.pause_circle),
                      label: Text(
                          a.status == AgentStatus.paused ? 'Resume' : 'Pause'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _delete,
                  icon: Icon(Icons.delete,
                      color: Theme.of(context).colorScheme.error),
                  label: Text('Delete',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
                const SizedBox(height: 16),
                Text('Activity history',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_activity.isEmpty)
                  const Text('No activity yet. Run a check to see the log.')
                else
                  ..._activity.map((e) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.circle, size: 8),
                        title: Text(e.message,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(_fmtTime(e.timestamp)),
                      )),
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13))),
        Expanded(
          child: GestureDetector(
            onLongPress: () =>
                Clipboard.setData(ClipboardData(text: value)),
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ]),
    );
  }

  static String _fmtTime(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
