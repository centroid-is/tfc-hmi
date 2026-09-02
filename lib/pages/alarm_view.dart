import 'package:flutter/material.dart';
import '../widgets/base_scaffold.dart';
import '../widgets/alarm.dart';
import '../widgets/stop_timeline.dart';
import 'package:tfc_dart/core/alarm.dart';

class AlarmViewPage extends StatefulWidget {
  const AlarmViewPage({Key? key}) : super(key: key);

  @override
  State<AlarmViewPage> createState() => _AlarmViewPageState();
}

class _AlarmViewPageState extends State<AlarmViewPage> {
  AlarmActive? _selectedAlarm;

  /// Active, history — or the stop analysis, which is the same alarm system
  /// read as downtime instead of as a list. It lives here as a sub-view
  /// because the question it answers ("why was the line down?") is asked on
  /// this page, not on a mimic page.
  AlarmViewMode _mode = AlarmViewMode.active;

  /// Set once the operator has closed the detail pane on purpose; from then
  /// on the page stops choosing for them until they pick an alarm again.
  bool _operatorCleared = false;

  void _setMode(AlarmViewMode mode) {
    setState(() {
      _mode = mode;
      // A different reading is a different question; the selection belonged
      // to the old one.
      _selectedAlarm = null;
    });
  }

  void _onActiveAlarms(List<AlarmActive> active) {
    if (_operatorCleared) return;
    final current = _selectedAlarm;
    // Keep a selection that is still active; replace one that has cleared
    // (or none at all) with the worst of what is active now.
    if (current != null &&
        active.any((a) => a.notification.uid == current.notification.uid)) {
      return;
    }
    final pick = mostCriticalAlarm(active);
    if (pick?.notification.uid == current?.notification.uid) return;
    setState(() => _selectedAlarm = pick);
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == AlarmViewMode.stops) {
      return BaseScaffold(
        title: 'Stop Analysis',
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The same control the list header carries, so leaving the
              // stop view is the same gesture as entering it.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AlarmViewModeSegments(
                    selected: AlarmViewMode.stops,
                    onChanged: _setMode,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Expanded(child: StopTimeline()),
            ],
          ),
        ),
      );
    }
    return BaseScaffold(
      title: 'Active Alarms',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Active Alarms List (left pane)
            Expanded(
              flex: 2,
              child: ListActiveAlarms(
                mode: _mode,
                onModeChanged: _setMode,
                onShow: (alarm) {
                  setState(() {
                    _selectedAlarm = alarm;
                    _operatorCleared = false;
                  });
                },
                onActiveAlarms: _onActiveAlarms,
              ),
            ),
            const SizedBox(width: 24),
            // Active Alarm View (right pane)
            Expanded(
              flex: 3,
              child: _selectedAlarm != null
                  ? ViewActiveAlarm(
                      alarm: _selectedAlarm!,
                      onClose: () {
                        setState(() {
                          _selectedAlarm = null;
                          _operatorCleared = true;
                        });
                      },
                    )
                  : Center(
                      child: Text(
                        'Select an alarm to view details',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The alarm to show when the operator has not picked one: the most severe
/// active alarm, newest first within a level. Arriving on the page to an
/// empty "Select an alarm" pane when something IS wrong was a wasted tap;
/// the worst thing on the line is what they came to read.
AlarmActive? mostCriticalAlarm(List<AlarmActive> active) {
  if (active.isEmpty) return null;
  final sorted = [...active]..sort((a, b) {
      final byLevel = b.notification.rule.level.index
          .compareTo(a.notification.rule.level.index);
      if (byLevel != 0) return byLevel;
      return b.notification.timestamp.compareTo(a.notification.timestamp);
    });
  return sorted.first;
}
