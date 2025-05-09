import 'package:flutter/material.dart';
import '../widgets/alarm.dart';
import '../widgets/base_scaffold.dart';
import '../core/alarm.dart';

class AlarmEditorPage extends StatefulWidget {
  const AlarmEditorPage({Key? key}) : super(key: key);

  @override
  State<AlarmEditorPage> createState() => _AlarmEditorPageState();
}

class _AlarmEditorPageState extends State<AlarmEditorPage> {
  AlarmConfig? _edit;
  AlarmConfig? _show;
  bool _create = false;

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Alarms Editor',
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alarm List (left pane)
            Expanded(
              flex: 2,
              child: ListAlarms(
                onEdit: (config) {
                  setState(() {
                    _edit = config;
                    _show = null;
                    _create = false;
                  });
                },
                onShow: (config) {
                  setState(() {
                    _show = config;
                    _edit = null;
                    _create = false;
                  });
                },
                onCreate: () {
                  setState(() {
                    _create = true;
                    _edit = null;
                    _show = null;
                  });
                },
                onDelete: (config) {
                  setState(() {
                    if (_edit?.uid == config.uid) {
                      _edit = null;
                    }
                    if (_show?.uid == config.uid) {
                      _show = null;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 24),
            // Editor Form (right pane)
            Expanded(
              flex: 3,
              child: _edit != null
                  ? EditAlarm(
                      config: _edit!,
                      onSubmit: () {
                        setState(() {
                          _edit = null;
                        });
                      },
                    )
                  : _show != null
                      ? AlarmForm(
                          initialConfig: _show!,
                          submitText: 'Close',
                          onSubmit: (config) {
                            setState(() {
                              _show = null;
                            });
                          },
                        )
                      : _create
                          ? CreateAlarm(
                              onSubmit: () {
                                setState(() {
                                  _create = false;
                                });
                              },
                            )
                          : Center(
                              child: Text(
                                '',
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
