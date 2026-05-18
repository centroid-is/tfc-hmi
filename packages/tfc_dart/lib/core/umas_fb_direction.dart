/// Function-block (FB) member direction classification for UMAS.
///
/// Phase 3 (VAR_INPUT / VAR_OUTPUT distinction) owns the classifier
/// itself. This file provides the [UmasFbMemberDirection] enum and a
/// minimal [classifyFbMemberDirection] entry point so Phase 5
/// (VAR_IN_OUT stretch — see `umas_var_in_out.dart`) and Phase 4
/// (UI affordances) can depend on the data model without waiting on
/// Phase 3's implementation to merge.
///
/// plc4j does not decode direction bytes (PLC4X
/// UmasUnlocatedVariableReference has `unknown5` / `unknown4`
/// opaque fields). The mapping below is inferred from observation
/// of M580 FB layouts and pinned by
/// `test/core/umas_fb_direction_test.dart`. See
/// `.planning/phases/03-var_input-var_output-distinction/03-RESEARCH.md`
/// for full provenance (Phase 3 deliverable; not present in this
/// worktree).
library;

/// Direction of an FB member declared in the IEC 61131-3 sense.
enum UmasFbMemberDirection {
  /// `VAR_INPUT` — readable; the FB receives this value from the
  /// caller.
  input,

  /// `VAR_OUTPUT` — readable; the FB writes this value back.
  output,

  /// `VAR_IN_OUT` — backed by a pointer; direct memory reads return
  /// 0x94. Mark unreadable per Phase 5 / FB-05 path (b).
  inOut,

  /// Public `VAR` member (non-IN_OUT, non-INPUT, non-OUTPUT) —
  /// readable.
  publicVar,

  /// Direction bytes did not match any known table entry. Surface
  /// as an undecorated leaf rather than a silent miscategorisation.
  unknown,
}

/// Classify the direction of an FB member based on the two opaque
/// 16-bit fields (`unknown5`, `unknown4`) that follow `(dataType,
/// offset)` in a DD02 per-member record header.
///
/// Mapping (empirical, pinned by tests):
///
///   unknown5  unknown4   direction
///   0x0001    *          input
///   0x0002    *          output
///   0x0003    *          inOut
///   0x0000    0x0000     publicVar
///   else      else       unknown
///
/// `unknown` is a deliberate catch-all: when the wire bytes do not
/// match a known direction, we surface the member as undecorated
/// rather than silently miscategorising. The UI can render
/// `unknown` distinctly from `publicVar` if desired (Phase 4).
UmasFbMemberDirection classifyFbMemberDirection(int unknown5, int unknown4) {
  switch (unknown5 & 0xFFFF) {
    case 0x0001:
      return UmasFbMemberDirection.input;
    case 0x0002:
      return UmasFbMemberDirection.output;
    case 0x0003:
      return UmasFbMemberDirection.inOut;
    case 0x0000:
      // publicVar requires BOTH bytes to be zero — a non-zero
      // unknown4 with unknown5==0 has not been observed and is
      // intentionally classified as `unknown` so a wrong mapping
      // surfaces as undecorated UI rather than as silent
      // miscategorisation.
      if ((unknown4 & 0xFFFF) == 0x0000) {
        return UmasFbMemberDirection.publicVar;
      }
      return UmasFbMemberDirection.unknown;
    default:
      return UmasFbMemberDirection.unknown;
  }
}
