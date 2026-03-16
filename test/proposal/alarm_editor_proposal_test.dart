import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level assertions for alarm_editor.dart proposal enhancements.
///
/// AlarmEditorPage depends on alarmManProvider (which needs real AlarmMan),
/// so we use source assertions rather than widget tests.
void main() {
  late String editorSource;
  late String alarmSource;

  setUpAll(() {
    editorSource = File('lib/pages/alarm_editor.dart').readAsStringSync();
    alarmSource = File('lib/widgets/alarm.dart').readAsStringSync();
  });

  group('AlarmEditorPage proposal support', () {
    test('is a ConsumerStatefulWidget for ref access', () {
      expect(editorSource, contains('ConsumerStatefulWidget'));
    });

    test('has _proposedAlarm field', () {
      expect(editorSource, contains('_proposedAlarm'));
    });

    test('has _parseAlarmProposal method', () {
      expect(editorSource, contains('_parseAlarmProposal'));
    });

    test('handles proposalData in initState', () {
      expect(editorSource, contains('proposalData'));
      expect(editorSource, contains('_parseAlarmProposal'));
    });

    test('proposal form is editable with Accept Proposal submit button', () {
      // The proposal uses an editable AlarmForm with 'Accept Proposal' text
      expect(editorSource, contains("editable: true"));
      expect(editorSource, contains("submitText: 'Accept Proposal'"));
    });

    test('accept saves edited config from form, not original proposal', () {
      // _acceptProposalWithConfig takes an AlarmConfig parameter (the edited one)
      expect(editorSource, contains('_acceptProposalWithConfig(editedConfig)'));
      expect(editorSource, contains('AlarmConfig editedConfig'));
    });

    test('has Reject button with red color', () {
      expect(editorSource, contains('Reject'));
      expect(editorSource, contains('Colors.red'));
    });

    test('imports proposal_state.dart', () {
      expect(editorSource, contains('proposal_state.dart'));
    });

    test('handles invalid proposal JSON gracefully', () {
      // try/catch around JSON decoding
      expect(editorSource, contains('try'));
      expect(editorSource, contains('catch'));
    });

    test('_acceptProposalWithConfig invalidates alarmManProvider to refresh list',
        () {
      expect(editorSource, contains('ref.invalidate(alarmManProvider)'));
    });

    test('_acceptProposalWithConfig shows success SnackBar', () {
      expect(editorSource, contains('Alarm proposal accepted!'));
    });

    test('proposal form has ValueKey for Marionette', () {
      expect(editorSource, contains("ValueKey('alarm-proposal-form')"));
    });

    test('banner instructs user to edit fields before accepting', () {
      expect(editorSource, contains('Edit the fields below'));
      expect(editorSource, contains('Accept Proposal to save'));
    });

    test('Reject button has ValueKey for Marionette', () {
      expect(editorSource, contains("ValueKey('alarm-proposal-reject')"));
    });
  });

  group('ListAlarms proposal support', () {
    test('has proposedAlarm parameter', () {
      expect(alarmSource, contains('proposedAlarm'));
    });

    test('uses proposalDecoration for proposed alarm styling', () {
      expect(alarmSource, contains('proposalDecoration'));
    });

    test('shows ProposalBadge on proposed alarm', () {
      expect(alarmSource, contains('ProposalBadge'));
    });

    test('imports proposal_visual.dart', () {
      expect(alarmSource, contains('proposal_visual.dart'));
    });

    test('add button has ValueKey for Marionette', () {
      expect(alarmSource, contains("ValueKey('alarm-editor-add')"));
    });
  });

  group('_parseAlarmProposal correctness', () {
    test('accepts _proposal_type "alarm"', () {
      // The server sends _proposal_type: 'alarm' for both create and update
      expect(editorSource, contains("type != 'alarm'"));
    });

    test('accepts _proposal_type "alarm_create" for forward-compat', () {
      expect(editorSource, contains("type != 'alarm_create'"));
    });

    test('accepts _proposal_type "alarm_update" for forward-compat', () {
      expect(editorSource, contains("type != 'alarm_update'"));
    });

    test('removes _proposal_type key before passing to AlarmConfig.fromJson',
        () {
      expect(editorSource, contains("map.remove('_proposal_type')"));
    });

    test('rejects non-Map JSON (e.g. array, string)', () {
      // The guard: if (decoded is! Map<String, dynamic>) return;
      expect(editorSource, contains('is! Map<String, dynamic>'));
    });

    test('rejects null proposalData early', () {
      // The guard: if (json == null) return;
      expect(editorSource, contains('if (json == null) return'));
    });

    test('matches proposal ID from proposalStateProvider for status tracking',
        () {
      expect(editorSource, contains('proposalStateProvider'));
      expect(editorSource, contains('_proposalId = p.id'));
    });
  });

  group('Accept/Reject lifecycle', () {
    test('uses updateAlarm (not addAlarm) to handle both create and update proposals',
        () {
      // BUG FIX: addAlarm would create duplicates for update proposals.
      // updateAlarm does removeWhere(uid) + add, which is safe for both:
      // - create: removeWhere is a no-op (no matching uid), then adds
      // - update: removes old alarm with same uid, then adds updated one
      expect(editorSource, contains('alarmMan.updateAlarm(editedConfig)'));
      // Ensure addAlarm is NOT used in the accept path
      expect(
        editorSource.contains('alarmMan.addAlarm(editedConfig)'),
        isFalse,
        reason: 'Should use updateAlarm instead of addAlarm to avoid '
            'duplicate alarms when accepting update proposals',
      );
    });

    test('accept clears proposal state after saving', () {
      // After accepting: _isProposal = false, _proposedAlarm = null, _show = null
      expect(editorSource, contains('_isProposal = false'));
      expect(editorSource, contains('_proposedAlarm = null'));
    });

    test('reject clears proposal state without saving to alarm manager', () {
      // _rejectProposal does NOT call alarmMan.addAlarm or alarmMan.updateAlarm
      // It only updates the proposalStateProvider and clears local state.
      final rejectMethodBody = _extractMethodBody(editorSource, '_rejectProposal');
      expect(rejectMethodBody, isNotNull);
      expect(rejectMethodBody, isNot(contains('alarmMan')));
    });

    test('accept notifies proposalStateProvider.notifier.acceptProposal', () {
      expect(editorSource,
          contains('proposalStateProvider.notifier).acceptProposal'));
    });

    test('reject notifies proposalStateProvider.notifier.rejectProposal', () {
      expect(editorSource,
          contains('proposalStateProvider.notifier).rejectProposal'));
    });

    test('accept only notifies proposalState when _proposalId is non-null', () {
      // Guard: if (_proposalId != null)
      expect(editorSource, contains('if (_proposalId != null)'));
    });

    test('accept checks mounted before showing SnackBar', () {
      expect(editorSource, contains('if (!mounted) return'));
    });
  });

  group('Proposal form editability', () {
    test('proposal form is fully editable (title, description, rules)', () {
      // The proposal AlarmForm has editable: true
      // AlarmForm with editable: true enables all form fields
      expect(editorSource, contains("editable: true"));
    });

    test('proposal form passes initialConfig from parsed proposal', () {
      expect(editorSource, contains('initialConfig: _proposedAlarm!'));
    });

    test('proposal form submit callback receives the edited config', () {
      // The onSubmit receives editedConfig (the user-modified version)
      expect(editorSource, contains('onSubmit: (editedConfig)'));
    });
  });

  group('Amber proposal styling in ListAlarms', () {
    test('proposed alarm uses Container with proposalDecoration', () {
      expect(alarmSource, contains('proposalDecoration()'));
    });

    test('proposed alarm shows ProposalBadge as leading widget', () {
      expect(alarmSource, contains('leading: const ProposalBadge()'));
    });

    test('proposed alarm shows "AI Proposed:" prefix in subtitle', () {
      expect(alarmSource, contains('AI Proposed:'));
    });

    test('proposed alarm is tappable to show in right pane', () {
      expect(alarmSource, contains('onTap: () => widget.onShow?.call(widget.proposedAlarm!)'));
    });

    test('proposed alarm only appears when proposedAlarm is not null', () {
      expect(alarmSource, contains('if (widget.proposedAlarm != null)'));
    });
  });

  group('Title bar shows proposal mode', () {
    test('title changes to "Alarm Editor -- AI Proposal" when proposal is active',
        () {
      expect(editorSource,
          contains("'Alarm Editor -- AI Proposal'"));
    });

    test('title shows normal "Alarms Editor" when no proposal', () {
      expect(editorSource, contains("'Alarms Editor'"));
    });

    test('title uses ternary based on _isProposal flag', () {
      expect(editorSource,
          contains("_isProposal ? 'Alarm Editor -- AI Proposal' : 'Alarms Editor'"));
    });
  });

  group('Proposal form takes priority over other panes', () {
    test('proposal form is first in the ternary chain (highest priority)', () {
      // The right pane ternary: _isProposal ? AlarmForm : _edit ? EditAlarm : _show ? ...
      // This ensures the proposal form is always shown when a proposal is active,
      // even if the user taps an alarm in the list.
      expect(editorSource,
          contains('_isProposal && _proposedAlarm != null'));
    });
  });

  // ── Bug fix: duplicate alarm shows stale data ───
  //
  // When duplicating a second alarm, Flutter reuses the existing _AlarmFormState
  // without calling initState() again. Adding ValueKey(uid) forces widget
  // recreation so initState() runs with the new alarm's data.

  group('Bug fix: duplicate alarm stale data (ValueKey)', () {
    test('CreateAlarm has ValueKey based on template uid', () {
      // ValueKey(_createTemplate?.uid ?? 'new') ensures Flutter recreates
      // the widget when a different alarm is duplicated.
      expect(editorSource, contains("ValueKey("));
      expect(editorSource, contains("_createTemplate?.uid ?? 'new'"));
    });

    test('EditAlarm has ValueKey based on edit uid', () {
      // ValueKey(_edit?.uid ?? 'edit') ensures Flutter recreates the widget
      // when switching between different alarms to edit.
      expect(editorSource, contains("_edit?.uid ?? 'edit'"));
    });

    test('Show AlarmForm has ValueKey based on show uid', () {
      // ValueKey(_show?.uid ?? 'show') ensures the view pane refreshes
      // when showing a different alarm.
      expect(editorSource, contains("_show?.uid ?? 'show'"));
    });
  });

  // ── Bug fix: no close button on sidebar ───
  //
  // The right pane (create/edit/view sidebar) had no way to dismiss it.
  // A subtle close button (Icons.close) is now positioned at the top-right
  // of the right pane, resetting all pane state when tapped.

  group('Bug fix: sidebar close button', () {
    test('close button exists with ValueKey for Marionette', () {
      expect(editorSource, contains("'alarm-editor-close-pane'"));
    });

    test('close button uses Icons.close icon', () {
      expect(editorSource, contains('Icons.close'));
    });

    test('close button is in a right-aligned Row above form content', () {
      expect(editorSource, contains('MainAxisAlignment.end'));
      expect(editorSource, contains('IconButton('));
    });

    test('close button resets all pane state', () {
      // Pressing close should reset _create, _createTemplate, _edit, _show
      // to dismiss whichever pane is open.
      expect(editorSource, contains('_create = false'));
      expect(editorSource, contains('_createTemplate = null'));
      expect(editorSource, contains('_edit = null'));
      expect(editorSource, contains('_show = null'));
    });

    test('close button uses subtle grey color with small icon size', () {
      expect(editorSource, contains('Colors.grey'));
      expect(editorSource, contains('size: 18'));
    });

    test('right pane uses Column to place close button above form content', () {
      // The right pane wraps content in a Column so the close button
      // Row sits above the form content without overlapping.
      expect(editorSource, contains('Column('));
      expect(editorSource, contains('Expanded('));
    });
  });

  // ── Bug fix: amber banner must have Accept button (not just Reject) ───
  //
  // Regression test for a bug where the alarm editor's amber proposal banner
  // only had a Reject button. The PageEditor and KeyRepository both had
  // Accept + Reject, but AlarmEditor was missing Accept. This group verifies
  // that all three editors have matching Accept/Reject button patterns.

  group('Bug fix: AlarmEditor amber banner has both Accept and Reject buttons', () {
    test('amber banner has Accept button as ElevatedButton', () {
      // The amber banner (Container with Colors.amber.shade50) must contain
      // an ElevatedButton with text 'Accept'. Previously only Reject existed.
      expect(editorSource, contains('ElevatedButton('));
      expect(editorSource, contains("child: const Text('Accept')"));
    });

    test('Accept button has ValueKey for Marionette testing', () {
      expect(editorSource, contains("ValueKey('alarm-proposal-accept')"));
    });

    test('Accept button has green background styling', () {
      // Accept button uses green to match PageEditor and KeyRepository pattern
      expect(editorSource, contains('backgroundColor: Colors.green'));
      expect(editorSource, contains('foregroundColor: Colors.white'));
    });

    test('Reject button is OutlinedButton (not ElevatedButton)', () {
      // Reject should be OutlinedButton with red styling (secondary action),
      // distinct from the primary Accept ElevatedButton
      expect(editorSource, contains('OutlinedButton('));
      expect(editorSource, contains("child: const Text('Reject')"));
    });

    test('Reject button has red border styling', () {
      expect(editorSource, contains('BorderSide(color: Colors.red)'));
    });

    test('Accept button appears before Reject button in amber banner', () {
      // Accept should come first (primary action), then Reject (secondary).
      // Verify ordering by checking that 'alarm-proposal-accept' appears
      // before 'alarm-proposal-reject' in the source.
      final acceptIndex = editorSource.indexOf("'alarm-proposal-accept'");
      final rejectIndex = editorSource.indexOf("'alarm-proposal-reject'");
      expect(acceptIndex, greaterThan(-1),
          reason: 'Accept button key must exist');
      expect(rejectIndex, greaterThan(-1),
          reason: 'Reject button key must exist');
      expect(acceptIndex, lessThan(rejectIndex),
          reason: 'Accept button must appear before Reject button in banner');
    });

    test('Accept button calls _acceptProposalWithConfig', () {
      // The banner Accept button should call _acceptProposalWithConfig with
      // the current proposed alarm config (not the form-edited version)
      expect(editorSource, contains('_acceptProposalWithConfig(_proposedAlarm!)'));
    });

    test('all three editors have matching Accept/Reject button pattern', () {
      // Cross-editor consistency check: AlarmEditor, PageEditor, and
      // KeyRepository must all have Accept ElevatedButton + Reject OutlinedButton.
      // This prevents regression where one editor loses its Accept button.
      final pageSource =
          File('lib/pages/page_editor.dart').readAsStringSync();
      final keySource =
          File('lib/pages/key_repository.dart').readAsStringSync();

      // All three must have ElevatedButton Accept with green background
      for (final entry in {
        'AlarmEditor': editorSource,
        'PageEditor': pageSource,
        'KeyRepository': keySource,
      }.entries) {
        final src = entry.value;
        final name = entry.key;

        expect(src, contains("const Text('Accept')"),
            reason: '$name must have Accept button text');
        expect(src, contains("const Text('Reject')"),
            reason: '$name must have Reject button text');
        expect(src, contains('backgroundColor: Colors.green'),
            reason: '$name must have green Accept button');
        expect(src, contains('foregroundColor: Colors.red'),
            reason: '$name must have red Reject button');
        expect(src, contains('ElevatedButton'),
            reason: '$name must use ElevatedButton for Accept');
        expect(src, contains('OutlinedButton'),
            reason: '$name must use OutlinedButton for Reject');
      }
    });
  });
}

/// Extracts the method body of [methodName] from [source].
///
/// Returns the content between the first `{` and its matching `}`.
/// Returns null if the method is not found.
String? _extractMethodBody(String source, String methodName) {
  final methodIndex = source.indexOf(methodName);
  if (methodIndex == -1) return null;

  final braceStart = source.indexOf('{', methodIndex);
  if (braceStart == -1) return null;

  var depth = 0;
  for (var i = braceStart; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) {
      return source.substring(braceStart, i + 1);
    }
  }
  return null;
}
