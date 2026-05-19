/// Live-calibrated byte-pattern → direction truth table.
///
/// These pinned cases were captured on 2026-05-18 against the live M580
/// at 192.168.112.159 using `tools/umas_direction_calibration.dart`.
/// Each row is `(unknown5, unknown4) -> direction`; the comment names
/// the FB member whose live record produced that byte pattern (the
/// Schneider naming-convention prefix is the ground-truth oracle).
///
/// The classifier in `packages/tfc_dart/lib/core/umas_fb_direction.dart`
/// ships the byte mapping verified by these cases. The names are NOT
/// consulted by the production classifier — they are documentation only.
///
/// If a future firmware or PLC project breaks one of these rows, the
/// fix is to re-run the calibration harness, update the table here, and
/// update the classifier — not to add a name-based fallback in
/// production.
import 'package:test/test.dart';
import 'package:tfc_dart/core/umas_fb_direction.dart';

void main() {
  group('umas direction — live-calibrated byte → direction (M580 @ '
      '192.168.112.159, 2026-05-18)', () {
    // ─── input (i_*) ────────────────────────────────────────────────
    test('// i_xUp on FB returned unknown5=0x0000 unknown4=0x0001', () {
      expect(classifyFbMemberDirection(0x0000, 0x0001),
          UmasFbMemberDirection.input);
    });
    test('// i_xDwn, i_xFreshness, i_xFwd, i_xRev, i_xAuto, i_xCleaning, '
        'i_uiAcc, i_uiDec, i_xManFwd, i_xManRev, i_xReset, i_xPermManFwd, '
        'i_xSensor, i_xAlarmNeeded — 15 inputs all returned unk4=0x0001', () {
      // Same byte pattern as i_xUp — pinned once is sufficient, but the
      // test name documents the population that produced this row.
      expect(classifyFbMemberDirection(0x0000, 0x0001),
          UmasFbMemberDirection.input);
    });
    test('// i_stDTM returned unknown4=0x0201 — upper byte ignored, '
        'lower byte 0x01 still classifies as input', () {
      expect(classifyFbMemberDirection(0x0000, 0x0201),
          UmasFbMemberDirection.input);
    });

    // ─── output (q_*) ──────────────────────────────────────────────
    test('// q_rVelocity, q_xUp, q_xDwn, q_xSensor, q_xSensorBlocked '
        '— 5 outputs returned unk5=0x0000 unk4=0x0003', () {
      expect(classifyFbMemberDirection(0x0000, 0x0003),
          UmasFbMemberDirection.output);
    });

    // ─── publicVar (p_* declared) ──────────────────────────────────
    test('// p_cmd_manUp, p_cmd_manDwn, p_stat_upSensor, p_stat_dwnSensor, '
        'p_Stat_xReset, p_Stat_rPos, p_Cfg_tTonDelay, p_Cfg_tTofDelay, '
        'p_Stat_xSensor, p_Stat_xSensorBlocked — 10 declared publicVars '
        'all returned unk5=0x0000 unk4=0x0004', () {
      expect(classifyFbMemberDirection(0x0000, 0x0004),
          UmasFbMemberDirection.publicVar);
    });

    // ─── publicVar (zero-marker internal counters) ─────────────────
    test('// p_Stat_iThermalFaults, p_Stat_diRuntime — internal counters '
        'returned unk5=0x0000 unk4=0x0000 (zero-marker publicVar)', () {
      expect(classifyFbMemberDirection(0x0000, 0x0000),
          UmasFbMemberDirection.publicVar);
    });

    // ─── No-convention UDT struct members ──────────────────────────
    test('// ETH_STATUS, SERVICE_STATUS, FDR_USAGE, IN_PACKETS, ETA, '
        'RFR, LCR, HMIS, LFT, AI3C, CMD, LFR, ACC, DEC, etc. — UDT struct '
        'fields without an IN/OUT/VAR keyword also surface as unk4=0x0000. '
        'These get publicVar from the bytes; F-1 gating in the parser '
        '(parentClassId==7) keeps them undecorated when the parent is a '
        'UDT (classId==2) rather than an FB (classId==7).', () {
      expect(classifyFbMemberDirection(0x0000, 0x0000),
          UmasFbMemberDirection.publicVar);
    });

    // ─── Coverage gap: inOut (iq_* / io_*) ─────────────────────────
    test('// no live sample for inOut; speculative mapping 0x0005 -> inOut '
        'pinned for forward compatibility (will be re-verified the next '
        'time we calibrate against a PLC that exposes iq_/io_ members)', () {
      expect(classifyFbMemberDirection(0x0000, 0x0005),
          UmasFbMemberDirection.inOut);
    });

    // ─── Safety: unfamiliar patterns collapse to unknown ───────────
    test('// unfamiliar lower byte (0x02) -> unknown — silent '
        'miscategorisation would be worse than undecorated UI', () {
      expect(classifyFbMemberDirection(0x0000, 0x0002),
          UmasFbMemberDirection.unknown);
    });
    test('// non-zero unknown5 -> unknown — outside calibrated sample', () {
      expect(classifyFbMemberDirection(0x0001, 0x0001),
          UmasFbMemberDirection.unknown);
    });
  });
}
