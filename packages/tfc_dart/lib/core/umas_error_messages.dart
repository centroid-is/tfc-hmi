/// TD-018 (v1.1.x): shared UMAS error → operator-friendly message
/// translation. Used by both the Flutter Browse dialog
/// (`lib/widgets/umas_browse.dart`) and the headless CLI
/// (`packages/tfc_dart/tool/umas_cli.dart`) so the same hex code
/// produces the same actionable hint everywhere.
///
/// Previously the Browse dialog had a rich error mapper (translating
/// 0x83 → "Data Dictionary not enabled — open EcoStruxure → Tools →
/// Project Settings..."), while the CLI only printed raw hex. The
/// verify-script gating loop (`tools/v1.1-verify.sh`) routinely sees
/// these errors and operators had to learn the protocol codes by
/// heart to diagnose.
///
/// This file lives in `tfc_dart/core/` (no Flutter dependency) so the
/// CLI and other headless tooling can consume it directly.
library;

import 'umas_types.dart';

/// Operator-friendly translation of a UMAS error.
///
/// - [summary]: one-line description suitable for status bars / CLI
///   stderr lines ("0x83: Data Dictionary not enabled").
/// - [detail]: multi-paragraph actionable guidance (steps to fix in
///   EcoStruxure, firmware version notes, etc.). Suitable for an
///   expandable dialog or `--verbose` CLI output.
class UmasErrorInfo {
  final String summary;
  final String detail;
  const UmasErrorInfo({required this.summary, required this.detail});
}

/// Translate a thrown error into a [UmasErrorInfo], or null when the
/// error is not a UMAS protocol error (caller should fall through to
/// generic exception handling).
UmasErrorInfo? mapUmasError(Object error) {
  if (error is! UmasException) return null;
  final hex = '0x${error.errorCode.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  if (error.errorCode == 0x83) {
    return UmasErrorInfo(
      summary: '$hex: UMAS not available — Data Dictionary likely disabled',
      detail: 'The PLC responded to FC90 but rejected the request with '
          'status $hex. This typically means the Data Dictionary is not '
          'enabled in the project.\n\n'
          'To fix this in Unity Pro / EcoStruxure Control Expert:\n\n'
          '1. Open your PLC project\n'
          '2. Go to Tools → Project Settings → PLC embedded data\n'
          '3. Enable "Data Dictionary"\n'
          '4. Download the updated project to the PLC\n'
          '5. Retry browsing\n\n'
          'Also check that your PLC firmware is v2.60 or newer '
          '(older firmware has known UMAS issues).',
    );
  }

  if (error.errorCode == 0xC0) {
    return UmasErrorInfo(
      summary: '$hex: Data Dictionary not accessible',
      detail: 'The PLC connection works (session established) but the '
          'Data Dictionary is not accessible. Error $hex means the PLC '
          'project does not have variable browsing enabled.\n\n'
          'To fix this in EcoStruxure Control Expert:\n\n'
          '1. Open your PLC project\n'
          '2. Go to Tools → Project Settings → PLC embedded data\n'
          '3. Check "Allow Data Dictionary Read"\n'
          '4. Rebuild and download the project to the PLC\n'
          '5. Retry browsing\n\n'
          'Note: Without the Data Dictionary, you can still use '
          'direct register addressing (holding registers, coils) '
          'by entering addresses manually.',
    );
  }

  if (error.errorCode == 0x06) {
    return UmasErrorInfo(
      summary: '$hex: Another client holds the PLC reservation',
      detail: 'The PLC currently has an exclusive write reservation held '
          'by another client (typically EcoStruxure Control Expert '
          'connected for monitoring or download). UMAS only permits one '
          'reservation at a time.\n\n'
          'Options:\n\n'
          '1. Disconnect the other client (close EcoStruxure or any other '
          'HMI that holds the reservation)\n'
          '2. Wait for the other client to release the reservation\n'
          '3. Cycle PLC power as a last resort (forfeits the reservation)\n\n'
          'Read operations (browse, monitor) do NOT require a reservation '
          'and should still work; only write operations are blocked.',
    );
  }

  if (error.errorCode == 0x86) {
    return UmasErrorInfo(
      summary: '$hex: Write rejected (value out of range or invalid type)',
      detail: 'The PLC rejected the write with status $hex. Common causes:\n\n'
          '- Value exceeds the variable\'s declared range (e.g. writing '
          '40000 to an INT, which maxes at 32767)\n'
          '- Type mismatch (e.g. writing a string to a numeric variable)\n'
          '- STRING write exceeded the declared STRING(N) length\n'
          '- Read-only variable (input, public-read, or constant)\n\n'
          'Check the variable\'s declared data type in EcoStruxure and '
          'verify the value fits.',
    );
  }

  if (error.errorCode == 0x94) {
    return UmasErrorInfo(
      summary: '$hex: Address invalid or VAR_IN_OUT not readable',
      detail: 'The PLC rejected the request with status $hex. This usually '
          'means one of:\n\n'
          '- The (block, offset) address does not exist in the running '
          'project — the variable was deleted or moved by a recent '
          'redownload, and the symbol cache is stale.\n'
          '- The variable is a VAR_IN_OUT, which is pointer-backed and '
          'cannot be read/written directly via UMAS.\n'
          '- The variable is a folder/struct/FB node rather than a leaf '
          'scalar; only leaves can be read directly.\n\n'
          'If the project was recently redownloaded, retry after the '
          'symbol cache rebuilds (next 30s tick).',
    );
  }

  if (error.errorCode == 0xA1) {
    return UmasErrorInfo(
      summary: '$hex: ReadVariable not supported on this firmware',
      detail: 'The PLC rejected ReadVariable (0x22) with status $hex. On '
          'M580 firmware this is the standard signal to use MonitorPlc '
          '(0x50) instead — the client should auto-detect and switch '
          'transparently. If you see this on a stable read, the '
          'auto-fallback may have failed.\n\n'
          'Workarounds: cycle the TCP connection so the adapter rebuilds, '
          'or verify the firmware version supports MonitorPlc (v2.60+).',
    );
  }

  // Generic UMAS error — at least surface the hex code with a hint.
  return UmasErrorInfo(
    summary: '$hex: UMAS error — ${error.message}',
    detail: 'The PLC returned UMAS error code $hex.\n\n'
        'If this is unexpected, verify that:\n'
        '- The PLC supports UMAS (M340/M580 with Unity firmware)\n'
        '- Data Dictionary is enabled in the PLC project\n'
        '- The PLC firmware is up to date',
  );
}
