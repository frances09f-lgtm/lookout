/// Shared "one card per check cycle" history model and card.
///
/// Used by both the dedicated history screen and the task detail screen's
/// inline history so every surface groups the same way. A check cycle's log
/// lines all share one exact timestamp (the checker passes a single `at` to
/// every logActivity call of a cycle), so identical timestamps define a cycle.
import 'package:flutter/material.dart';

import '../domain/activity.dart';
import 'expressive.dart';

/// Groups activity entries (already filtered to one task) into cycles.
/// Ids are monotonic in write order, so a cycle's lines read in the order
/// they happened (list sort is not stable on equal times).
List<HistoryCycle> groupHistoryCycles(List<ActivityEntry> items) {
  final byStamp = <int, List<ActivityEntry>>{};
  for (final e in items) {
    byStamp.putIfAbsent(e.timestamp.millisecondsSinceEpoch, () => []).add(e);
  }
  return [
    for (final entries in byStamp.values)
      HistoryCycle(
        entries: entries..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0)),
      ),
  ];
}

String fmtHistoryTime(DateTime t) =>
    '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The honest outcome of one check cycle, derived only from what was logged.
enum CycleState { updated, noResult, failed, notMet, met }

class HistoryCycle {
  final List<ActivityEntry> entries;
  HistoryCycle({required this.entries});

  DateTime get at => entries.first.timestamp;

  bool _has(String prefix) => entries.any((e) => e.message.startsWith(prefix));

  /// Lines only an actual check run writes. Their absence means the group
  /// is an edit/save event, not a check - never render one as the other.
  static const _checkMarkers = [
    'Started check',
    'Fetched data',
    'Clock checked',
    'Manual value checked',
    'Unable to check',
    'Condition met',
    'Condition not met',
  ];

  CycleState get state {
    if (!_checkMarkers.any(_has)) return CycleState.updated;
    if (_has('Unable to check')) return CycleState.failed;
    if (_has('Condition met')) return CycleState.met;
    if (_has('Condition not met')) return CycleState.notMet;
    return CycleState.noResult;
  }

  /// A check that started but never recorded any outcome, long enough ago
  /// that it is not merely still running. Signals an interrupted check
  /// (process killed mid-run) rather than an edit or a completed cycle.
  bool get looksInterrupted =>
      state == CycleState.noResult &&
      _has('Started check') &&
      DateTime.now().difference(at).inMinutes > 2;

  String get title => switch (state) {
    CycleState.updated => 'Task updated',
    CycleState.failed => 'Unable to check',
    CycleState.met => 'Condition met',
    CycleState.notMet => 'Condition not met',
    CycleState.noResult => 'Started check',
  };

  String get badge => switch (state) {
    CycleState.updated => 'Saved',
    CycleState.failed => 'Failed',
    CycleState.met => 'Done',
    CycleState.notMet => 'Not yet',
    CycleState.noResult => 'No result',
  };

  (Color, Color) get colors => switch (state) {
    CycleState.updated => (XColors.sky, XColors.skyDeep),
    CycleState.failed => (XColors.peach, XColors.peachDeep),
    CycleState.met => (XColors.mint, XColors.mintDeep),
    CycleState.notMet => (XColors.sky, XColors.skyDeep),
    CycleState.noResult => (XColors.lavender, XColors.lavenderDeep),
  };

  IconData get icon => switch (state) {
    CycleState.updated => Icons.edit_outlined,
    CycleState.failed => Icons.warning_amber_rounded,
    CycleState.met => Icons.check_circle_outline,
    CycleState.notMet => Icons.check,
    CycleState.noResult => Icons.bolt,
  };

  /// Log lines shown inside the card. The state line itself is dropped (the
  /// title and badge already say it); its detail is kept without the prefix.
  List<CycleStep> get steps {
    final out = <CycleStep>[];
    for (final e in entries) {
      final m = e.message;
      if (m == 'Condition met' || m == 'Condition not met') continue;
      if (m == 'Started check' && state == CycleState.noResult) continue;
      if (m.startsWith('Unable to check: ')) {
        out.add(
          CycleStep(m.substring('Unable to check: '.length), CycleStepKind.value),
        );
      } else if (m.startsWith('Next check scheduled')) {
        out.add(CycleStep(m, CycleStepKind.next));
      } else if (m.startsWith('Read retry scheduled')) {
        out.add(CycleStep(m, CycleStepKind.retry));
      } else if (m.startsWith('Fetched data') ||
          m.startsWith('Clock checked') ||
          m.startsWith('Manual value checked')) {
        out.add(CycleStep(m, CycleStepKind.value));
      } else {
        out.add(CycleStep(m, CycleStepKind.normal));
      }
    }
    if (state == CycleState.noResult && out.isEmpty) {
      out.add(
        const CycleStep('No result recorded for this cycle', CycleStepKind.normal),
      );
    }
    return out;
  }
}

enum CycleStepKind { normal, value, next, retry }

class CycleStep {
  final String text;
  final CycleStepKind kind;
  const CycleStep(this.text, this.kind);
}

class CycleCard extends StatelessWidget {
  final HistoryCycle cycle;
  const CycleCard({super.key, required this.cycle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (pastel, deep) = cycle.colors;
    final dark = xIsDark(context);
    final nextColor = dark ? const Color(0xFF8FC3EE) : XColors.skyDeep;
    final retryColor = dark ? const Color(0xFFF0B98A) : XColors.peachDeep;
    final isNoResult = cycle.state == CycleState.noResult;
    final badgeBg = isNoResult
        ? theme.colorScheme.surfaceContainerHighest
        : pastel;
    final badgeFg = isNoResult ? theme.colorScheme.onSurfaceVariant : deep;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 13),
      decoration: BoxDecoration(
        color: xPanel(context),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: pastel,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(cycle.icon, size: 18, color: deep),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cycle.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fmtHistoryTime(cycle.at),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  cycle.badge.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: badgeFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 9),
          for (final step in cycle.steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      step.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13.5,
                        height: 1.35,
                        color: switch (step.kind) {
                          CycleStepKind.value => theme.colorScheme.onSurface,
                          CycleStepKind.next => nextColor,
                          CycleStepKind.retry => retryColor,
                          CycleStepKind.normal =>
                            theme.colorScheme.onSurfaceVariant,
                        },
                        fontWeight: switch (step.kind) {
                          CycleStepKind.value => FontWeight.w600,
                          CycleStepKind.next => FontWeight.w700,
                          CycleStepKind.retry => FontWeight.w700,
                          CycleStepKind.normal => FontWeight.w400,
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
