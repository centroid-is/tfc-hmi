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

  const AlarmEditorPage({Key? key, this.proposalData}) : super(key: key);

  @override
  ConsumerState<AlarmEditorPage> createState() => _AlarmEditorPageState();
}

class _AlarmEditorPageState extends ConsumerState<AlarmEditorPage> {
  AlarmConfig? _edit;
  AlarmConfig? _show;
  bool _create = false;
  AlarmConfig? _createTemplate;

  /// Proposals staged as a batch.
  ///
  /// An MCP client fires create_alarm one call per alarm, so a set of 38
  /// arrives as 38 proposals. Staging one at a time meant 38 separate
  /// reviews and 38 separate saves.
  /// The banner's callback slots, captured when publishing.
  ///
  /// Riverpod forbids `ref` inside dispose() -- "Cannot use ref after the
  /// widget was disposed" -- and these are plain (non-autoDispose)
  /// StateProviders, so their controllers outlive this State and can be held.
  StateController<Future<void> Function()?>? _commitSlot;
  StateController<Future<void> Function()?>? _discardSlot;

  final List<AlarmConfig> _proposedAlarms = [];
  final List<int> _proposalIds = [];

  /// Uids among [_proposedAlarms] that accepting should *remove*.
  ///
  /// Kept by uid rather than by index because a batch mixes creates, updates
  /// and deletes -- they arrive as separate MCP calls -- and the form pops
  /// entries off the front of the list as it accepts them one at a time.
  final Set<String> _proposedDeleteUids = {};

  bool get _isProposal => _proposedAlarms.isNotEmpty;

  /// Whether the alarm the form is showing is staged for removal.
  bool get _proposedIsDelete =>
      _proposedAlarm != null &&
      _proposedDeleteUids.contains(_proposedAlarm!.uid);

  /// The alarm the form edits: the first of the batch. Accepting from the
  /// form applies that one edited config and leaves the rest staged.
  AlarmConfig? get _proposedAlarm =>
      _proposedAlarms.isEmpty ? null : _proposedAlarms.first;

  @override
  void initState() {
    super.initState();
    if (_stageAlarmProposals() == 0) _stageRoutedProposal(widget.proposalData);
  }

  /// Stages the proposal the route carried, for callers that removed it from
  /// state before navigating.
  ///
  /// The chat batch card calls acceptAllOfType() -- which empties
  /// proposalStateProvider -- and only then beams here with the JSON in tow.
  /// Reading state alone would stage nothing and apply nothing, while every
  /// proposal in the batch had already been marked accepted.
  void _stageRoutedProposal(String? json) {
    if (json == null) return;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return;
      final map = Map<String, dynamic>.from(decoded)..remove('_proposal_type');
      final isDelete = map.remove('_op') == 'delete';
      final config = AlarmConfig.fromJson(map);
      _proposedAlarms.add(config);
      if (isDelete) _proposedDeleteUids.add(config.uid);
      _publishProposalCallbacks();
    } catch (_) {
      // Malformed JSON: nothing to stage.
    }
  }

  /// Stages every pending alarm proposal in one batch.
  ///
  /// Safe to re-enter: ids already staged are skipped, so a proposal landing
  /// after the first joins the batch instead of being dropped on the floor.
  ///
  /// Returns how many were newly staged.
  int _stageAlarmProposals() {
    var added = 0;
    try {
      final state = ref.read(proposalStateProvider);
      for (final p in state.proposals) {
        if (p.proposalType != 'alarm' &&
            p.proposalType != 'alarm_create' &&
            p.proposalType != 'alarm_update') {
          continue;
        }
        if (_proposalIds.contains(p.id)) continue;
        try {
          final decoded = jsonDecode(p.proposalJson);
          if (decoded is! Map<String, dynamic>) continue;
          final map = Map<String, dynamic>.from(decoded)
            ..remove('_proposal_type');
          // delete_alarm sends the whole config so it parses like any other
          // proposal; only `_op` says what accepting it does.
          final isDelete = map.remove('_op') == 'delete';
          final config = AlarmConfig.fromJson(map);
          _proposedAlarms.add(config);
          if (isDelete) _proposedDeleteUids.add(config.uid);
          _proposalIds.add(p.id);
          added++;
        } catch (_) {
          // A malformed proposal must not take the rest of the batch with it.
        }
      }
    } catch (_) {
      // Provider unavailable (tests) -- nothing to stage.
    }
    if (added > 0) _publishProposalCallbacks();
    return added;
  }

  /// Hands the black banner the commit/discard actions for this batch.
  ///
  /// The inline amber Accept/Reject bar that used to sit above the editor is
  /// gone: one place to act on a proposal, not two. The form below still
  /// offers "Accept Proposal" for the alarm being edited, which is a
  /// different job -- accepting an *edited* config.
  void _publishProposalCallbacks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final commitSlot = ref.read(proposalCommitProvider.notifier);
      commitSlot.state = _commitProposals;
      _commitSlot = commitSlot;
      final discardSlot = ref.read(proposalDiscardProvider.notifier);
      discardSlot.state = _discardProposals;
      _discardSlot = discardSlot;
    });
  }

  /// Applies every staged alarm, then marks the proposals accepted.
  Future<void> _commitProposals() async {
    if (_proposedAlarms.isEmpty) return;
    // Deliberately NOT wrapped in a try: a failure here must abort before
    // anything is marked accepted. Swallowing it and running the accept loop
    // anyway would write zero alarms and still mark all N proposals accepted,
    // which is exactly the loss the ordering below exists to prevent.
    final alarmMan = await ref.read(alarmManProvider.future);
    for (final a in _proposedAlarms) {
      // updateAlarm removes the uid then re-adds it, so routing a removal
      // through it would write the alarm straight back and delete nothing.
      if (_proposedDeleteUids.contains(a.uid)) {
        alarmMan.removeAlarm(a);
      } else {
        alarmMan.updateAlarm(a);
      }
    }
    ref.invalidate(alarmManProvider);

    // Awaited, and only after the alarms are in: acceptProposal marks the row
    // accepted in the database, so doing it first would lose them on failure.
    final notifier = ref.read(proposalStateProvider.notifier);
    for (final id in _proposalIds) {
      try {
        await notifier.acceptProposal(id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _proposedAlarms.clear();
      _proposalIds.clear();
      _proposedDeleteUids.clear();
      _show = null;
    });
    ref.read(proposalCommitProvider.notifier).state = null;
    ref.read(proposalDiscardProvider.notifier).state = null;
  }

  /// Drops the whole batch without adding any alarm.
  Future<void> _discardProposals() async {
    final notifier = ref.read(proposalStateProvider.notifier);
    for (final id in _proposalIds) {
      try {
        await notifier.rejectProposal(id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _proposedAlarms.clear();
      _proposalIds.clear();
      _proposedDeleteUids.clear();
      _show = null;
    });
    ref.read(proposalCommitProvider.notifier).state = null;
    ref.read(proposalDiscardProvider.notifier).state = null;
  }

  /// Accept the proposal with the (possibly edited) alarm config from the form.
  ///
  /// A removal goes through [AlarmMan.removeAlarm]; everything else through
  /// [AlarmMan.updateAlarm], which handles both create and update:
  /// - For new alarms (no matching UID): removeWhere is a no-op, then adds.
  /// - For updated alarms (matching UID): removes old, then adds updated.
  /// This avoids duplicate alarms when accepting an update proposal.
  Future<void> _acceptProposalWithConfig(AlarmConfig editedConfig) async {
    final removing = _proposedDeleteUids.contains(editedConfig.uid);
    try {
      final alarmMan = await ref.read(alarmManProvider.future);
      if (removing) {
        alarmMan.removeAlarm(editedConfig);
      } else {
        alarmMan.updateAlarm(editedConfig);
      }

      // Invalidate the provider so the alarm list rebuilds with the new alarm.
      ref.invalidate(alarmManProvider);
    } catch (_) {}

    // Only the alarm the form was editing leaves the batch; anything else
    // still staged stays for the banner to accept.
    if (_proposalIds.isNotEmpty) {
      // Removed only AFTER the await returns. Dropping it first meant a
      // failed accept left the id out of _proposalIds while still in state,
      // and the next listener tick re-staged it as a duplicate.
      final id = _proposalIds.first;
      await ref.read(proposalStateProvider.notifier).acceptProposal(id);
      _proposalIds.removeAt(0);
      // The flag leaves with the alarm it marks: dropping it earlier would
      // leave a still-staged removal looking like an ordinary update.
      if (_proposedAlarms.isNotEmpty) {
        _proposedDeleteUids.remove(_proposedAlarms.removeAt(0).uid);
      }
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(removing ? 'Alarm removed.' : 'Alarm proposal accepted!')),
    );

    setState(() {
      _show = null;
    });
    if (_proposedAlarms.isEmpty) {
      ref.read(proposalCommitProvider.notifier).state = null;
      ref.read(proposalDiscardProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    // The banner holds these closures over this State. Left set, "Accept all"
    // would call into a disposed State after navigating away: nothing saved,
    // proposals still pending, and an uncaught async error.
    _commitSlot?.state = null;
    _discardSlot?.state = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reactively watch for new alarm proposals arriving via MCP.
    ref.listen<ProposalState>(proposalStateProvider, (prev, next) {
      // No "already showing one" guard: a later proposal joins the batch.
      if (_stageAlarmProposals() > 0) setState(() {});
    });

    return BaseScaffold(
      title: _isProposal ? 'Alarm Editor -- AI Proposal' : 'Alarms Editor',
      body: Column(
        children: [
          // The inline amber Accept/Reject bar used to live here. Removed:
          // the black banner is the one place proposals are acted on. What
          // remains is a plain count, so a staged batch is still obvious.
          if (_isProposal)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_proposedAlarms.length == 1
                        ? _proposedIsDelete
                            ? 'AI proposal: remove ${_proposedAlarm!.title}'
                            : 'AI proposal: ${_proposedAlarm!.title}'
                        : '${_proposedAlarms.length} AI alarm proposals '
                            'staged - accept them from the banner above, or '
                            'edit this one below and accept it on its own.'),
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
                    child: _isProposal && _proposedAlarm != null
                        // Read-only for a removal: editing the fields of an
                        // alarm about to be deleted changes nothing, and the
                        // edited config would be what gets removed.
                        ? _proposedIsDelete
                            ? AlarmForm(
                                key: ValueKey(
                                    'alarm-removal-form-${_proposedAlarm!.uid}'),
                                initialConfig: _proposedAlarm!,
                                submitText: 'Remove Alarm',
                                onSubmit: (_) {
                                  _acceptProposalWithConfig(_proposedAlarm!);
                                },
                              )
                            : AlarmForm(
                                key: ValueKey(
                                    'alarm-proposal-form-${_proposedAlarm!.uid}'),
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
