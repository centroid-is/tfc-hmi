import 'package:flutter/material.dart';
import '../widgets/base_scaffold.dart';
import '../widgets/alarm.dart';
import 'package:tfc_dart/core/alarm.dart'
    if (dart.library.js_interop) 'package:tfc_dart/core/web_stubs/alarm_stub.dart';

class AlarmViewPage extends StatefulWidget {
  const AlarmViewPage({super.key});

  @override
  State<AlarmViewPage> createState() => _AlarmViewPageState();
}

class _AlarmViewPageState extends State<AlarmViewPage> {
  AlarmActive? _selectedAlarm;

  @override
  Widget build(BuildContext context) {
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
                onShow: (alarm) {
                  setState(() {
                    _selectedAlarm = alarm;
                  });
                },
                onViewChanged: () {
                  setState(() {
                    _selectedAlarm = null;
                  });
                },
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
