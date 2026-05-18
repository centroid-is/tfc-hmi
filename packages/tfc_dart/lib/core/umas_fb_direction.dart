/// Function-block (FB) member direction classification for UMAS.
///
/// Bytes-only classifier. Maps the two opaque uint16 LE fields that
/// follow `(dataType, offset)` in a DD02 per-member record header to an
/// [UmasFbMemberDirection]. plc4j calls these fields `unknown5` (bytes
/// 4-5) and `unknown4` (bytes 6-7) — see protocols/umas/.../umas.mspec.
///
/// The mapping was calibrated against the live M580 at 192.168.112.159
/// using `tools/umas_direction_calibration.dart`: the harness walks
/// every FB-member record and pairs each member's bytes with the
/// Schneider naming-convention prefix (`i_` / `q_` / `p_` / `iq_` /
/// `io_`) used in that project's PLC code, then prints an agreement
/// matrix. The shipping classifier follows the byte signal only — names
/// were a reverse-engineering oracle and are **not** consulted at
/// runtime.
///
/// Observed mapping on the M580 (counts from the live calibration):
///
/// | `unknown5` | `unknown4` lower byte | direction   | samples |
/// |-----------:|----------------------:|-------------|--------:|
/// |     0x0000 |                  0x01 | `input`     |      16 |
/// |     0x0000 |                  0x03 | `output`    |       5 |
/// |     0x0000 |                  0x04 | `publicVar` |      10 |
/// |     0x0000 |                  0x00 | `publicVar` |       2 |
/// |       else |             *anything | `unknown`   |       — |
///
/// `unknown5` is always zero on the M580; the direction signal lives in
/// the **lower byte** of `unknown4`. The upper byte of `unknown4` is
/// observed non-zero only once (`0x02` paired with input — `i_stDTM`)
/// and is ignored — likely an orthogonal flag (e.g. "is-DDT") that has
/// no bearing on direction.
///
/// `inOut` (VAR_IN_OUT, i.e. members named `iq_*` / `io_*`) does NOT
/// appear in the calibration sample on this PLC. The shipping
/// classifier maps `0x05` → `inOut` speculatively based on the lower
/// byte progression (`0x01`=in, `0x03`=out, `0x05`=in_out) plus plc4j's
/// VAR_IN_OUT marker convention; any unfamiliar pattern collapses to
/// `unknown` so an incorrect guess shows as undecorated UI rather than
/// silent miscategorisation.
///
/// F-1 v1.1: callers must gate this classifier on parent class
/// (classIdentifier==7 → FB members get a direction; ==2 → UDT struct
/// fields stay undecorated). The gate is in `_parseVariableRecords` /
/// `_readDD02Block` in `umas_client.dart`.
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

  /// Direction bytes did not match any known table entry. Surface as
  /// an undecorated leaf rather than a silent miscategorisation.
  unknown,
}

/// Classify the direction of an FB member based on the two opaque
/// 16-bit fields (`unknown5`, `unknown4`) that follow `(dataType,
/// offset)` in a DD02 per-member record header.
///
/// See the file header for the full live-calibrated byte→direction
/// table. The classifier is independent of any naming convention.
///
/// [unknown5] — uint16 LE at bytes 4-5 of the DD02 member record.
///   Always observed as 0x0000 on the M580 calibration target. Any
///   non-zero value collapses to `unknown` (safety: we don't have a
///   sample for what a non-zero upper word means).
///
/// [unknown4] — uint16 LE at bytes 6-7 of the DD02 member record. The
///   **lower byte** carries the direction code; the upper byte is
///   treated as an orthogonal flag and ignored.
UmasFbMemberDirection classifyFbMemberDirection(int unknown5, int unknown4) {
  // unknown5 must be zero — anything else is outside the calibrated
  // sample and stays unknown to avoid silent miscategorisation.
  if ((unknown5 & 0xFFFF) != 0x0000) {
    return UmasFbMemberDirection.unknown;
  }
  switch (unknown4 & 0xFF) {
    case 0x00:
      return UmasFbMemberDirection.publicVar;
    case 0x01:
      return UmasFbMemberDirection.input;
    case 0x03:
      return UmasFbMemberDirection.output;
    case 0x04:
      return UmasFbMemberDirection.publicVar;
    // SPECULATIVE — no live calibration sample for 0x05 on the M580.
    // Based on lower-byte progression (0x01=in, 0x03=out, 0x05=in_out)
    // and plc4j's UmasReadVariableInOutMember convention. If a future
    // PLC exposes 0x05 as something else, members will be silently
    // mis-labeled as VAR_IN_OUT.
    case 0x05:
      // Speculative: VAR_IN_OUT (PLC4J's UmasReadVariableInOutMember).
      // No live sample on this M580. Kept here so the lower-byte
      // progression is complete; collapses to `unknown` only if the
      // sample base expands and shows this maps elsewhere.
      return UmasFbMemberDirection.inOut;
    default:
      return UmasFbMemberDirection.unknown;
  }
}
