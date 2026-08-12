import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/alarm.dart';
import '../widgets/base_scaffold.dart';
import 'package:tfc_dart/core/alarm.dart';

class AlarmEditorPage extends ConsumerStatefulWidget {
  const AlarmEditorPage({Key? key}) : super(key: key);

  @override
  ConsumerState<AlarmEditorPage> createState() => _AlarmEditorPageState();
}

class _AlarmEditorPageState extends ConsumerState<AlarmEditorPage> {
  AlarmConfig? _edit;
  AlarmConfig? _show;
  bool _create = false;
  AlarmConfig? _createTemplate;

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      title: 'Alarms Editor',
      body: Column(
        children: [
          Expanded(
            child: Padding(
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
                      onCreate: (config_template) {
                        setState(() {
                          _create = true;
                          _createTemplate = config_template;
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
                    child: _edit != null || _show != null || _create
                        ? Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    key: const ValueKey(
                                        'alarm-editor-close-pane'),
                                    icon: const Icon(Icons.close, size: 18),
                                    color: Colors.grey,
                                    tooltip: 'Close',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    splashRadius: 14,
                                    onPressed: () {
                                      setState(() {
                                        _create = false;
                                        _createTemplate = null;
                                        _edit = null;
                                        _show = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              if (_edit != null)
                                Expanded(
                                  child: EditAlarm(
                                    key: ValueKey(_edit?.uid ?? 'edit'),
                                    config: _edit!,
                                    onSubmit: () {
                                      setState(() {
                                        _edit = null;
                                      });
                                    },
                                  ),
                                )
                              else if (_show != null)
                                Expanded(
                                  child: AlarmForm(
                                    key: ValueKey(_show?.uid ?? 'show'),
                                    initialConfig: _show!,
                                    submitText: 'Close',
                                    onSubmit: (config) {
                                      setState(() {
                                        _show = null;
                                      });
                                    },
                                  ),
                                )
                              else if (_create)
                                Expanded(
                                  child: CreateAlarm(
                                    key: ValueKey(
                                        _createTemplate?.uid ?? 'new'),
                                    template: _createTemplate,
                                    onSubmit: () {
                                      setState(() {
                                        _create = false;
                                      });
                                    },
                                  ),
                                ),
                            ],
                          )
                        : Center(
                            child: Text(
                              '',
                              style:
                                  Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
