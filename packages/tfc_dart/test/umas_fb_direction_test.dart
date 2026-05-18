@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_fb_direction.dart';
import 'package:tfc_dart/core/umas_var_in_out.dart';
import 'package:tfc_dart/core/umas_types.dart';

/// Phase 3 stub + Phase 5 / FB-05 path (b) contract tests.
///
/// [UmasFbMemberDirection] and [classifyFbMemberDirection] are Phase 3
/// territory (VAR_INPUT / VAR_OUTPUT distinction). Phase 5 owns the
/// VAR_IN_OUT-specific extensions: [unreadableReasonForDirection],
/// [isReadableForDirection], and the new fields on
/// [UmasVariableTreeNode] ([direction], [readable], [unreadableReason]).
///
/// The classifier mapping is inferred from observation of M580 FB
/// layouts; plc4j leaves the underlying bytes opaque. See
/// `umas_fb_direction.dart` for the table.
void main() {
  group('classifyFbMemberDirection (Phase 3 stub)', () {
    test('0x0001 -> input (VAR_INPUT)', () {
      expect(classifyFbMemberDirection(0x0001, 0x0000),
          UmasFbMemberDirection.input);
    });

    test('0x0002 -> output (VAR_OUTPUT)', () {
      expect(classifyFbMemberDirection(0x0002, 0x0000),
          UmasFbMemberDirection.output);
    });

    test('0x0003 -> inOut (VAR_IN_OUT)', () {
      expect(classifyFbMemberDirection(0x0003, 0x0000),
          UmasFbMemberDirection.inOut);
    });

    test('0x0000 + 0x0000 -> publicVar (public VAR)', () {
      expect(classifyFbMemberDirection(0x0000, 0x0000),
          UmasFbMemberDirection.publicVar);
    });

    test('unmapped combination -> unknown (catch-all)', () {
      expect(classifyFbMemberDirection(0x00FF, 0xAAAA),
          UmasFbMemberDirection.unknown);
    });

    test('input classification ignores unknown4 high half', () {
      // Once unknown5 matches a direction byte the unknown4 value
      // should not flip the classification — only publicVar
      // (unknown5==0) cares about unknown4. Pins the table semantics.
      expect(classifyFbMemberDirection(0x0001, 0xFFFF),
          UmasFbMemberDirection.input);
    });

    test('output classification ignores unknown4 high half', () {
      expect(classifyFbMemberDirection(0x0002, 0xFFFF),
          UmasFbMemberDirection.output);
    });

    test('non-zero unknown4 with unknown5=0 -> unknown (not publicVar)', () {
      // publicVar requires BOTH bytes to be zero; a non-zero
      // unknown4 with unknown5=0 is something we have not seen on
      // the wire — defer to `unknown` so wrong classifications
      // surface as undecorated UI rather than as silent
      // miscategorisation.
      expect(classifyFbMemberDirection(0x0000, 0x0001),
          UmasFbMemberDirection.unknown);
    });
  });

  // -------------------------------------------------------------
  // Phase 5 / FB-05 path (b) — VAR_IN_OUT graceful labeling.
  // -------------------------------------------------------------
  group('Phase 5 — VAR_IN_OUT graceful labeling (FB-05 path b)', () {
    test('isReadableForDirection: inOut is not readable', () {
      expect(isReadableForDirection(UmasFbMemberDirection.inOut), isFalse);
    });

    test('isReadableForDirection: input/output/publicVar/unknown are readable',
        () {
      expect(isReadableForDirection(UmasFbMemberDirection.input), isTrue);
      expect(isReadableForDirection(UmasFbMemberDirection.output), isTrue);
      expect(isReadableForDirection(UmasFbMemberDirection.publicVar), isTrue);
      expect(isReadableForDirection(UmasFbMemberDirection.unknown), isTrue);
    });

    test('unreadableReasonForDirection: inOut returns the FB-05 contract '
        'string', () {
      final reason = unreadableReasonForDirection(UmasFbMemberDirection.inOut);
      expect(reason, isNotNull);
      // FB-05 path (b) success criterion: reason mentions "VAR_IN_OUT"
      // and the 0x94 error code so operators can cross-reference
      // with `dump-array` traces.
      expect(reason, contains('VAR_IN_OUT'));
      expect(reason, contains('0x94'));
    });

    test('unreadableReasonForDirection: readable directions return null', () {
      expect(unreadableReasonForDirection(UmasFbMemberDirection.input), isNull);
      expect(
          unreadableReasonForDirection(UmasFbMemberDirection.output), isNull);
      expect(unreadableReasonForDirection(UmasFbMemberDirection.publicVar),
          isNull);
      expect(unreadableReasonForDirection(UmasFbMemberDirection.unknown),
          isNull);
    });

    test('UmasVariableTreeNode defaults: readable=true, no direction/reason',
        () {
      final node = UmasVariableTreeNode(
        name: 'foo',
        path: 'foo',
      );
      expect(node.readable, isTrue);
      expect(node.direction, isNull);
      expect(node.unreadableReason, isNull);
    });

    test('UmasVariableTreeNode: VAR_IN_OUT member encoded with full FB-05 '
        'contract', () {
      // This is the exact shape Phase 2's FB expander will produce
      // for a VAR_IN_OUT member when it merges. Phase 4's UI
      // searches for these fields to render the "not readable
      // (VAR_IN_OUT)" affordance.
      final direction = UmasFbMemberDirection.inOut;
      final node = UmasVariableTreeNode(
        name: 'iqRef',
        path: 'M_Elevator.iqRef',
        variable: const UmasVariable(
          name: 'iqRef',
          blockNo: 0x10,
          offset: 0x00,
          dataTypeId: 0x05,
        ),
        direction: direction,
        readable: isReadableForDirection(direction),
        unreadableReason: unreadableReasonForDirection(direction),
      );
      expect(node.direction, UmasFbMemberDirection.inOut);
      expect(node.readable, isFalse);
      expect(node.unreadableReason, contains('VAR_IN_OUT'));
      expect(node.unreadableReason, contains('0x94'));
      // Member is in the tree — NOT silently dropped (Phase 5
      // milestone criterion: "No silent omission either way.")
      expect(node.name, 'iqRef');
      expect(node.path, 'M_Elevator.iqRef');
    });

    test('readable input/output/publicVar members surface with no reason', () {
      for (final dir in [
        UmasFbMemberDirection.input,
        UmasFbMemberDirection.output,
        UmasFbMemberDirection.publicVar,
      ]) {
        final node = UmasVariableTreeNode(
          name: 'm',
          path: 'M.m',
          direction: dir,
          readable: isReadableForDirection(dir),
          unreadableReason: unreadableReasonForDirection(dir),
        );
        expect(node.readable, isTrue, reason: 'direction=$dir');
        expect(node.unreadableReason, isNull, reason: 'direction=$dir');
      }
    });
  });
}
