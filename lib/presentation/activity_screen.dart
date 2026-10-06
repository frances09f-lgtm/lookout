import 'package:flutter/material.dart';

import '../data/agent_repository.dart';
import '../domain/activity.dart';

class ActivityScreen extends StatelessWidget {
  final AgentRepository repo;
  const ActivityScreen({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: FutureBuilder<List<ActivityEntry>>(
        future: repo.recentActivity(limit: 200),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
                child: Text('No activity yet. Create an agent to get started.'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final e = items[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.bolt, size: 18),
                title: Text(e.message, style: const TextStyle(fontSize: 13)),
                subtitle:
                    Text('agent ${e.agentId} - ${_fmt(e.timestamp)}'),
              );
            },
          );
        },
      ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
