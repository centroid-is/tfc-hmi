import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_fb_direction.dart';
import 'package:tfc_dart/core/umas_var_in_out.dart';
import 'package:tfc_dart/core/umas_types.dart';

/// Unit tests for [classifyFbMemberDirection].
///
/// The classifier maps the two uint16 LE fields (`unknown5`, `unknown4`)
/// that follow `(dataType, offset)` in the DD02 per-member record header
/// to one of the [UmasFbMemberDirection] enum values.
///
/// The mapping was calibrated against the live M580 at 192.168.112.159
/// (Schneider IEC 61131-3 prefix oracle: `i_` → input, `q_` → output,
/// `p_` → publicVar). See
/// `tools/umas_direction_calibration.dart`. plc4j itself labels these
/// bytes `unknown5` / `unknown4` and leaves them inert; this classifier
/// owns the inference.
///
/// Concrete byte-pattern → direction cases captured from the live PLC
/// are pinned in `umas_fb_direction_table_test.dart`. These tests cover
/// the synthetic mapping rules (lower-byte semantics, unknown5 must be
/// zero, default-to-unknown for unfamiliar patterns).
void main() {
  group('classifyFbMemberDirection — synthetic byte rules', () {
    test('unknown5=0x0000, unknown4 lower byte 0x01 -> input', () {
      expect(
        classifyFbMemberDirection(0x0000, 0x0001),
        UmasFbMemberDirection.input,
      );
    });

    test('unknown5=0x0000, unknown4 lower byte 0x03 -> output', () {
      expect(
        classifyFbMemberDirection(0x0000, 0x0003),
        UmasFbMemberDirection.output,
      );
    });

    test('unknown5=0x0000, unknown4 lower byte 0x04 -> publicVar (declared p_*)', () {
      expect(
        classifyFbMemberDirection(0x0000, 0x0004),
        UmasFbMemberDirection.publicVar,
      );
    });

    test('unknown5=0x0000, unknown4=0x0000 -> publicVar (internal counter)', () {
      expect(
        classifyFbMemberDirection(0x0000, 0x0000),
        UmasFbMemberDirection.publicVar,
      );
    });

    test('unknown5=0x0000, unknown4 lower byte 0x05 -> inOut (speculative)', () {
      expect(
        classifyFbMemberDirection(0x0000, 0x0005),
        UmasFbMemberDirection.inOut,
      );
    });

    test('unmapped lower byte -> unknown (catch-all)', () {
      expect(
        classifyFbMemberDirection(0x0000, 0x0002),
        UmasFbMemberDirection.unknown,
      );
      expect(
        classifyFbMemberDirection(0x0000, 0x00AA),
        UmasFbMemberDirection.unknown,
      );
    });

    test('non-zero unknown5 -> unknown (outside calibrated sample)', () {
      // Live M580 calibration showed unknown5 is always 0x0000. Any
      // non-zero value is outside the sample and stays unknown to avoid
      // silent miscategorisation.
      expect(
        classifyFbMemberDirection(0x0001, 0x0001),
        UmasFbMemberDirection.unknown,
      );
      expect(
        classifyFbMemberDirection(0xFFFF, 0x0000),
        UmasFbMemberDirection.unknown,
      );
    });

    test('input classification ignores unknown4 upper byte', () {
      // Live observation: `i_stDTM` had unknown4=0x0201. Upper byte
      // (0x02) is treated as an orthogonal flag and ignored — direction
      // is determined by the lower byte alone.
      expect(
        classifyFbMemberDirection(0x0000, 0x0201),
        UmasFbMemberDirection.input,
      );
      expect(
        classifyFbMemberDirection(0x0000, 0xFF01),
        UmasFbMemberDirection.input,
      );
    });

    test('output classification ignores unknown4 upper byte', () {
      expect(
        classifyFbMemberDirection(0x0000, 0xFF03),
        UmasFbMemberDirection.output,
      );
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
