/// TD-018 (v1.1.x): tests for the shared UMAS error → operator-friendly
/// message mapper. Used by both the Flutter Browse dialog and the
/// `tools/v1.1-verify.sh` CLI gating loop, so the contract has to be
/// nailed down in one place.
@TestOn('vm')
library;

import 'package:tfc_dart/core/umas_error_messages.dart';
import 'package:tfc_dart/core/umas_types.dart';
import 'package:test/test.dart';

void main() {
  group('TD-018: mapUmasError', () {
    test('non-UMAS errors return null (caller falls through)', () {
      expect(mapUmasError('not a UMAS error'), isNull);
      expect(mapUmasError(Exception('generic')), isNull);
      expect(mapUmasError(42), isNull);
    });

    test('0x83 maps to Data Dictionary disabled guidance', () {
      final info = mapUmasError(const UmasException(
        errorCode: 0x83,
        message: 'plcStatus failed: 0x83',
      ));
      expect(info, isNotNull);
      expect(info!.summary, contains('0x83'));
      expect(info.summary.toLowerCase(), contains('data dictionary'));
      expect(info.detail.toLowerCase(), contains('ecostruxure'));
      expect(info.detail.toLowerCase(), contains('project settings'));
    });

    test('0xC0 maps to Data Dictionary not accessible guidance', () {
      final info = mapUmasError(const UmasException(
        errorCode: 0xC0,
        message: 'browse failed: 0xC0',
      ));
      expect(info, isNotNull);
      expect(info!.summary, contains('0xC0'));
      expect(info.detail.toLowerCase(), contains('allow data dictionary'));
    });

    test('0x06 maps to reservation-conflict guidance', () {
      final info = mapUmasError(const UmasException(
        errorCode: 0x06,
        message: 'reservation conflict',
      ));
      expect(info, isNotNull);
      expect(info!.summary.toLowerCase(), contains('reservation'));
      expect(info.detail.toLowerCase(), contains('ecostruxure'));
    });

    test('0x81 (M580 dialect) maps to reservation-conflict guidance', () {
      // /tmp/umas-fuzz/fuzz-reservation.md: live M580 returns 0x81 while
      // another HMI holds the lock. Catalog must share the 0x06 mapping
      // so operators see the same actionable hint.
      final info = mapUmasError(const UmasException(
        errorCode: 0x81,
        message: 'reservation conflict (M580)',
      ));
      expect(info, isNotNull);
      expect(info!.summary, contains('0x81'));
      expect(info.summary.toLowerCase(), contains('reservation'));
      expect(info.detail.toLowerCase(), contains('ecostruxure'));
    });

    test('0x86 maps to write-rejected guidance', () {
      final info = mapUmasError(const UmasException(
        errorCode: 0x86,
        message: 'write failed: 0x86',
      ));
      expect(info, isNotNull);
      expect(info!.summary.toLowerCase(), contains('write'));
      expect(info.detail.toLowerCase(), contains('range'));
    });

    test('0x94 maps to address-invalid / VAR_IN_OUT guidance', () {
      final info = mapUmasError(const UmasException(
        errorCode: 0x94,
        message: 'address not found: 0x94',
      ));
      expect(info, isNotNull);
      expect(info!.summary.toLowerCase(), anyOf(
        contains('address'),
        contains('var_in_out'),
      ));
    });

    test('0xA1 maps to ReadVariable-not-supported guidance', () {
      final info = mapUmasError(const UmasException(
        errorCode: 0xA1,
        message: 'readVariable failed: 0xA1',
        secondaryErrorCode: 0xA1,
      ));
      expect(info, isNotNull);
      expect(info!.summary, contains('0xA1'));
      expect(info.detail.toLowerCase(), contains('monitorplc'));
    });

    test('unknown error codes get generic summary with hex code', () {
      final info = mapUmasError(const UmasException(
        errorCode: 0x42,
        message: 'something unexpected',
      ));
      expect(info, isNotNull);
      expect(info!.summary, contains('0x42'));
      expect(info.summary, contains('something unexpected'));
    });

    test('UmasReservationException (subclass) also resolves to 0x06 mapping',
        () {
      final info = mapUmasError(const UmasReservationException(
        errorCode: 0x06,
        message: 'Another client holds the PLC reservation',
      ));
      expect(info, isNotNull);
      expect(info!.summary.toLowerCase(), contains('reservation'));
    });
  });
}
