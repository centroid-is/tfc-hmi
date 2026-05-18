import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_fb_direction.dart';

/// Unit tests for [classifyFbMemberDirection].
///
/// The classifier maps the two uint16 LE fields (`unknown5`, `unknown4`)
/// that follow `(dataType, offset)` in the DD02 per-member record header
/// to one of the [UmasFbMemberDirection] enum values.
///
/// The mapping is inferred from empirical observation of M580 FB layouts
/// (see `.planning/phases/03-var_input-var_output-distinction/03-RESEARCH.md`).
/// plc4j itself does not decode these bytes — it labels them `unknown5` /
/// `unknown4` and leaves them inert. Phase 3 owns the inference.
void main() {
  group('classifyFbMemberDirection', () {
    test('0x0001 -> input (VAR_INPUT)', () {
      expect(
        classifyFbMemberDirection(0x0001, 0x0000),
        UmasFbMemberDirection.input,
      );
    });

    test('0x0002 -> output (VAR_OUTPUT)', () {
      expect(
        classifyFbMemberDirection(0x0002, 0x0000),
        UmasFbMemberDirection.output,
      );
    });

    test('0x0003 -> inOut (VAR_IN_OUT)', () {
      expect(
        classifyFbMemberDirection(0x0003, 0x0000),
        UmasFbMemberDirection.inOut,
      );
    });

    test('0x0000 + 0x0000 -> publicVar (public VAR)', () {
      expect(
        classifyFbMemberDirection(0x0000, 0x0000),
        UmasFbMemberDirection.publicVar,
      );
    });

    test('unmapped combination -> unknown (catch-all)', () {
      expect(
        classifyFbMemberDirection(0x00FF, 0xAAAA),
        UmasFbMemberDirection.unknown,
      );
    });

    test('input classification ignores unknown4 high half', () {
      // Once unknown5 matches a direction byte the unknown4 value should
      // not flip the classification — only publicVar (unknown5==0) cares
      // about unknown4. Pins the table semantics.
      expect(
        classifyFbMemberDirection(0x0001, 0xFFFF),
        UmasFbMemberDirection.input,
      );
    });

    test('output classification ignores unknown4 high half', () {
      expect(
        classifyFbMemberDirection(0x0002, 0xFFFF),
        UmasFbMemberDirection.output,
      );
    });

    test('non-zero unknown4 with unknown5=0 -> unknown (not publicVar)', () {
      // publicVar requires BOTH bytes to be zero; a non-zero unknown4 with
      // unknown5=0 is something we have not seen on the wire — defer to
      // `unknown` so wrong classifications surface as undecorated UI
      // rather than as silent miscategorisation.
      expect(
        classifyFbMemberDirection(0x0000, 0x0001),
        UmasFbMemberDirection.unknown,
      );
    });
  });
}
