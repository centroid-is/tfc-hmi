import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/page_creator/assets/helper/atv320_diagnostics.dart';

/// The ATV320 status decode is only worth anything if it agrees with the PLC.
///
/// The two code lists below are transcribed from the enums the drives are
/// actually read into — `hmis_e.TcDUT` and `lft_e.TcDUT` in
/// `sildarvinnsla/SVNCoreComponents/SVNCoreComponents/motors/ATV320/`. If the
/// PLC gains a code, this test fails until the HMI table gains it too, which
/// is the whole point: a fault the operator sees as a bare number is a fault
/// nobody acts on.
const _hmisCodes = <int>[
  0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 14, 15, 17, //
  18, 19, 20, 21, 22, 23, 25, 30, 35, 36, 37, 99,
];

const _lftCodes = <int>[
  0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 15, 16, 17, 18, 19, 20, 21, 22, 23, //
  24, 25, 26, 27, 28, 29, 30, 32, 33, 34, 37, 38, 40, 41, 42, 44, 45, 49,
  51, 52, 53, 54, 55, 56, 58, 59, 60, 64, 68, 69, 71, 72, 73, 77, 79, 80,
  81, 99, 100, 101, 105, 106, 107, 110, 111, 112, 113, 114, 115, 116, 117,
  119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 142,
  143, 144, 146, 148, 149, 150, 151, 152, 153, 154, 155, 157, 158, 159, 160,
  161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
  176, 177, 179, 180, 181, 182, 186, 190, 191, 192, 193, 200, 201, 203, 206,
  208, 211,
];

void main() {
  group('coverage of the PLC enums', () {
    test('every hmis_e code decodes to a named state', () {
      for (final code in _hmisCodes) {
        final e = atv320DriveState(code);
        expect(e.code, code);
        expect(e.label, isNotEmpty);
        expect(e.mnemonic, isNotEmpty);
        expect(e.meaning, isNotEmpty);
        expect(e.label, isNot(contains('Unrecognised')),
            reason: 'hmis_e code $code is in the PLC but not in the HMI '
                'table, so the pane would show a bare number');
      }
    });

    test('every lft_e code decodes to a named fault', () {
      for (final code in _lftCodes) {
        final e = atv320Fault(code);
        expect(e.code, code);
        expect(e.label, isNotEmpty);
        expect(e.mnemonic, isNotEmpty);
        expect(e.label, isNot(contains('Unrecognised')),
            reason: 'lft_e code $code is in the PLC but not in the HMI table');
      }
    });

    test('every fault except "no fault" carries a remedy', () {
      for (final code in _lftCodes.where((c) => c != 0)) {
        expect(atv320Fault(code).remedy, isNotEmpty,
            reason: 'fault $code tells the operator nothing to do');
      }
    });

    test('faults documented for the ATV320 state their reset class', () {
      // Without this an operator cannot tell whether the pane's Fault reset
      // button is worth pressing.
      for (final code in _lftCodes.where((c) => c != 0)) {
        final e = atv320Fault(code);
        if (!e.documented) continue;
        expect(e.clearing, isNotNull,
            reason: '${e.mnemonic} does not say what clears it');
      }
    });
  });

  group('drive state', () {
    test('ready is healthy and needs no advice', () {
      final e = atv320DriveState(2);
      expect(e.mnemonic, 'RDY');
      expect(e.label, 'Ready');
      expect(e.severity, Atv320Severity.ok);
      expect(e.isHealthy, isTrue);
    });

    test('running is healthy', () {
      expect(atv320DriveState(4).label, 'Running');
      expect(atv320DriveState(4).severity, Atv320Severity.ok);
    });

    test('current limit warns rather than faults — the belt still runs', () {
      final e = atv320DriveState(7);
      expect(e.mnemonic, 'CLI');
      expect(e.severity, Atv320Severity.warning);
      expect(e.remedy, isNotEmpty);
    });

    test('STO is a warning about the safety chain, not a drive trip', () {
      final e = atv320DriveState(30);
      expect(e.mnemonic, 'STO');
      expect(e.label, 'Safe Torque Off');
      expect(e.severity, Atv320Severity.warning);
      expect(e.remedy.join(' ').toLowerCase(), contains('emergency stop'));
    });

    test('FLT points the operator at the fault row', () {
      final e = atv320DriveState(23);
      expect(e.mnemonic, 'FLT');
      expect(e.severity, Atv320Severity.fault);
      expect(e.remedy.join(' ').toLowerCase(), contains('last fault'));
    });

    test(
      'code 99 is the PLC saying it lost the drive, not a drive state',
      () {
        // FB_ATV320 substitutes hmis_e.lost when the EtherCAT link is down or
        // the slave is not at OP. Reading it as an ATV320 state sends an
        // electrician into a drive that is fine.
        final e = atv320DriveState(99);
        expect(e.mnemonic, 'LOST');
        expect(e.severity, Atv320Severity.fault);
        expect(e.meaning.toLowerCase(), contains('ethercat'));
        expect(e.remedy.join(' ').toLowerCase(), contains('powered'));
      },
    );
  });

  group('faults', () {
    test('no fault is healthy', () {
      final e = atv320Fault(0);
      expect(e.mnemonic, 'NOF');
      expect(e.isHealthy, isTrue);
      expect(e.clearing, isNull);
    });

    test('overcurrent leads with the mechanical check, not with reset', () {
      final e = atv320Fault(9);
      expect(e.mnemonic, 'OCF');
      expect(e.label, 'Overcurrent');
      expect(e.clearing, Atv320Clearing.faultReset);
      expect(e.remedy.first.toLowerCase(), contains('jam'));
    });

    test('overspeed cannot be cleared from the pane', () {
      // SOF is in NVE41295's "requires a power reset" table; telling an
      // operator to press Fault reset would waste a trip to the machine.
      expect(atv320Fault(24).clearing, Atv320Clearing.powerCycle);
    });

    test('undervoltage clears itself', () {
      expect(atv320Fault(22).mnemonic, 'USF');
      expect(atv320Fault(22).clearing, Atv320Clearing.selfClears);
    });

    test('CNF explains the PLC-side substitution', () {
      final e = atv320Fault(7);
      expect(e.mnemonic, 'CNF');
      expect(e.meaning.toLowerCase(), contains('no link to drive'));
    });

    test('a short circuit warns against a blind reset', () {
      expect(atv320Fault(23).remedy.first.toLowerCase(),
          contains('do not simply reset'));
    });

    test('family codes are named but admit they are undocumented', () {
      // 126 (DRYF, dry run) exists in lft_e because the enum spans the whole
      // Altivar range. A conveyor drive will not raise it, and we do not
      // invent a remedy for it.
      final e = atv320Fault(126);
      expect(e.mnemonic, 'DRYF');
      expect(e.label, 'Dry run error');
      expect(e.documented, isFalse);
      expect(e.meaning, contains('not documented for the ATV320'));
      expect(e.remedy, isNotEmpty);
    });
  });

  group('codes outside the enums', () {
    test('an unknown fault code is reported, not guessed at', () {
      final e = atv320Fault(9999);
      expect(e.code, 9999);
      expect(e.label, contains('9999'));
      expect(e.documented, isFalse);
      expect(e.severity, Atv320Severity.warning);
    });

    test('an unknown drive state is reported too', () {
      final e = atv320DriveState(77);
      expect(e.label, contains('77'));
      expect(e.documented, isFalse);
    });
  });
}
