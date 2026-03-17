import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/alarm.dart';
import '../widgets/base_scaffold.dart';
import 'package:tfc_dart/core/alarm.dart';
import '../providers/alarm.dart';
import '../providers/proposal_state.dart';

class AlarmEditorPage extends ConsumerStatefulWidget {
  /// Optional proposal JSON passed via Beamer route data.
  final String? proposalData;

  const AlarmEditorPage({super.key, this.proposalData});

  @override
  ConsumerState<AlarmEditorPage> createState() => _AlarmEditorPageState();
}

class _AlarmEditorPageState extends ConsumerState<AlarmEditorPage> {
  AlarmConfig? _edit;
  AlarmConfig? _show;
  bool _create = false;
  AlarmConfig? _createTemplate;

  /// The proposed alarm parsed from proposalData.
  AlarmConfig? _proposedAlarm;
  int? _proposalId;
  bool _isProposal = false;

  @override
  void initState() {
    super.initState();
    _parseAlarmProposal(widget.proposalData);
  }

  /// Parses alarm proposal JSON into an [AlarmConfig].
  ///
  /// Sets [_proposedAlarm] and [_isProposal] on success.
  /// Gracefully handles invalid JSON without crashing.
  void _parseAlarmProposal(String? json) {
    if (json == null) return;

    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return;

      final type = decoded['_proposal_type'] as String?;
      if (type != 'alarm' && type != 'alarm_create' && type != 'alarm_update') {
        return;
      }

      // Remove the _proposal_type key before passing to AlarmConfig
      final map = Map<String, dynamic>.from(decoded);
      map.remove('_proposal_type');

      _proposedAlarm = AlarmConfig.fromJson(map);
      _isProposal = true;

      // Match against universal proposal state for ID tracking.
      try {
        final state = ref.read(proposalStateProvider);
        for (final p in state.proposals) {
          if (p.proposalJson == json) {
            _proposalId = p.id;
            break;
          }
        }
      } catch (_) {}
    } catch (_) {
      // Graceful: malformed JSON ignored, show normal editor.
    }
  }

  /// Accept the proposal with the (possibly edited) alarm config from the form.
  ///
  /// Uses [AlarmMan.updateAlarm] which handles both create and update:
  /// - For new alarms (no matching UID): removeWhere is a no-op, then adds.
  /// - For updated alarms (matching UID): removes old, then adds updated.
  /// This avoids duplicate alarms when accepting an update proposal.
  Future<void> _acceptProposalWithConfig(AlarmConfig editedConfig) async {
    try {
      final alarmMan = await ref.read(alarmManProvider.future);
      alarmMan.updateAlarm(editedConfig);

      // Invalidate the provider so the alarm list rebuilds with the new alarm.
      ref.invalidate(alarmManProvider);
    } catch (_) {}

    if (_proposalId != null) {
      try {
        ref.read(proposalStateProvider.notifier).acceptProposal(_proposalId!);
      } catch (_) {}
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alarm proposal accepted!')),
    );

    setState(() {
      _isProposal = false;
      _proposedAlarm = null;
      _show = null;
    });
  }

  void _rejectProposal() {
    if (_proposalId != null) {
      try {
        ref.read(proposalStateProvider.notifier).rejectProposal(_proposalId!);
      } catch (_) {}
    }

    setState(() {
      _isProposal = false;
      _proposedAlarm = null;
      _show = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reactively watch for new alarm proposals arriving via MCP.
    ref.listen<ProposalState>(proposalStateProvider, (prev, next) {
      if (_isProposal) return; // Already showing a proposal.
      final alarmProposals = next.proposals.where((p) =>
          p.proposalType == 'alarm' ||
          p.proposalType == 'alarm_create' ||
          p.proposalType == 'alarm_update');
      if (alarmProposals.isEmpty) return;
      final proposal = alarmProposals.first;
      _parseAlarmProposal(proposal.proposalJson);
      if (_isProposal) setState(() {});
    });

    return BaseScaffold(
      title: _isProposal ? 'Alarm Editor -- AI Proposal' : 'Alarms Editor',
      body: Column(
        children: [
          if (_isProposal && _proposedAlarm != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'AI Proposal: ${_proposedAlarm!.title}. '
                      'Edit the fields below, then click Accept Proposal to save.',
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const ValueKey('alarm-proposal-accept'),
                    onPressed: () {
                      // Accept with the current proposed alarm config.
                      // If the operator has edited fields in the form below,
                      // the form's own "Accept Proposal" submit button captures
                      // those edits. This banner button accepts the original
                      // proposal as-is.
                      _acceptProposalWithConfig(_proposedAlarm!);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Accept'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: const ValueKey('alarm-proposal-reject'),
                    onPressed: _rejectProposal,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ),
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
                      proposedAlarm: _proposedAlarm,
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
                      onCreate: (configTemplate) {
                        setState(() {
                          _create = true;
                          _createTemplate = configTemplate;
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
                    child: _isProposal && _proposedAlarm != null
                        ? AlarmForm(
                            key: const ValueKey('alarm-proposal-form'),
                            initialConfig: _proposedAlarm!,
                            editable: true,
                            submitText: 'Accept Proposal',
                            onSubmit: (editedConfig) {
                              _acceptProposalWithConfig(editedConfig);
                            },
                          )
                        : _edit != null || _show != null || _create
                            ? Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        key: const ValueKey(
                                            'alarm-editor-close-pane'),
                                        icon: const Icon(Icons.close,
                                            size: 18),
                                        color: Colors.grey,
                                        tooltip: 'Close',
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints(),
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
                                        key: ValueKey(
                                            _edit?.uid ?? 'edit'),
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
                                        key: ValueKey(
                                            _show?.uid ?? 'show'),
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
                                        key: ValueKey(_createTemplate?.uid ?? 'new'),
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
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
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
