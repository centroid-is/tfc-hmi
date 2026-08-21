/// Plain-language explanations for the two ATV320 status words the drives
/// publish to the HMI: `p_stat_State` (the keypad's HMIS drive state) and
/// `p_stat_LastFault` (the LFT fault record).
///
/// Both arrive as integers. The numbering is not ours to invent — it comes
/// from the PLC enums `hmis_e` and `lft_e` in
/// `SVNCoreComponents/motors/ATV320/`, which is what the drives are read
/// into. The wording of [Atv320Explanation.meaning] and
/// [Atv320Explanation.remedy] comes from the *ATV320 Programming Manual*
/// (Schneider NVE41295), chapter 11 "Diagnostics and Troubleshooting", so an
/// electrician reading the pane and an electrician reading the keypad are
/// looking at the same sentences.
///
/// Two deliberate limits:
///
///  * `lft_e` carries the whole Altivar family's fault list — pump, cabinet
///    and active-front-end codes an ATV320 on a conveyor cannot produce.
///    Those get a name and an honest "not documented for the ATV320" note
///    rather than an invented remedy. See [Atv320Explanation.documented].
///  * A code outside the enum is reported as-is instead of being guessed at.
///
/// This file holds no widgets on purpose — it is a lookup table, and the
/// colours for [Atv320Severity] belong to the theme at the call site.
library;

import 'package:flutter/foundation.dart';

/// How much operator attention a decoded value deserves.
///
/// Maps onto `HmiStateColors` at the call site — never to a raw `Colors.*`.
enum Atv320Severity {
  /// Normal, healthy — running or ready.
  ok,

  /// A transient or informational state; nothing to do.
  info,

  /// Running, but something is worth watching or will trip if ignored.
  warning,

  /// The drive has tripped, or cannot drive the motor.
  fault,
}

/// What it takes to get the drive out of a fault, per NVE41295 chapter 11.
///
/// This is the single most useful thing to tell an operator: whether the
/// `Fault reset` button in this pane can do anything at all.
enum Atv320Clearing {
  /// Goes away by itself once the cause does. No reset needed.
  selfClears,

  /// Clears with the pane's `Fault reset` (or the automatic restart), once
  /// the cause is gone.
  faultReset,

  /// Needs the drive powered down and back up after the cause is fixed —
  /// `Fault reset` will not clear it.
  powerCycle,
}

/// A decoded HMIS state or LFT fault: short words for the row, longer words
/// for the panel behind it.
@immutable
class Atv320Explanation {
  /// The raw enum ordinal, as published by the PLC.
  final int code;

  /// What the drive keypad shows, e.g. `RDY`, `OCF`. Kept so the pane and
  /// the physical drive can be cross-referenced.
  final String mnemonic;

  /// The short words for the row itself, e.g. `Ready`, `Overcurrent`.
  final String label;

  /// One or two sentences: what this state actually means on the line.
  final String meaning;

  /// What to do about it, one bullet per step. Empty when there is nothing
  /// to do (a healthy state).
  final List<String> remedy;

  /// Colour weight for the row.
  final Atv320Severity severity;

  /// Reset class. Null for drive states and for the no-fault entry.
  final Atv320Clearing? clearing;

  /// False when NVE41295 does not document this code for the ATV320 — the
  /// name is real (it comes from the PLC enum) but the cause and remedy are
  /// not ours to state. The UI says so rather than inventing advice.
  final bool documented;

  const Atv320Explanation({
    required this.code,
    required this.mnemonic,
    required this.label,
    required this.meaning,
    required this.severity,
    this.remedy = const [],
    this.clearing,
    this.documented = true,
  });

  /// True when the drive is in its ordinary, nothing-to-see-here condition.
  bool get isHealthy => severity == Atv320Severity.ok;
}

// ---------------------------------------------------------------------------
// HMIS — drive state (`hmis_e`)
// ---------------------------------------------------------------------------

/// Decodes `p_stat_State` (HMIS).
///
/// Returns an "unknown code" entry rather than null for a value outside
/// `hmis_e`, so the caller always has something to render.
Atv320Explanation atv320DriveState(int code) =>
    _driveStates[code] ?? _unknown(code, 'drive state');

const Map<int, Atv320Explanation> _driveStates = {
  0: Atv320Explanation(
    code: 0,
    mnemonic: 'TUN',
    label: 'Auto-tuning',
    meaning: 'The drive is measuring the motor windings. The motor may hum '
        'or twitch, but it will not run the belt.',
    severity: Atv320Severity.info,
    remedy: ['Wait for the measurement to finish — it takes a few seconds.'],
  ),
  1: Atv320Explanation(
    code: 1,
    mnemonic: 'DCB',
    label: 'DC braking',
    meaning: 'The drive is pushing DC through the motor to brake it to a '
        'standstill and hold it there.',
    severity: Atv320Severity.info,
  ),
  2: Atv320Explanation(
    code: 2,
    mnemonic: 'RDY',
    label: 'Ready',
    meaning: 'Powered, healthy and waiting for a run command. This is the '
        'normal state for a stopped belt.',
    severity: Atv320Severity.ok,
  ),
  3: Atv320Explanation(
    code: 3,
    mnemonic: 'NST',
    label: 'Freewheel stop',
    meaning: 'The motor is coasting — the drive is not holding it. Either no '
        'run command has been given, or an input assigned to freewheel/fast '
        'stop is off. These functions are active at zero volts on purpose, so '
        'a broken wire stops the belt.',
    severity: Atv320Severity.info,
    remedy: [
      'If the belt should be running, check that the section is calling for '
          'it and that the motor is in auto.',
      'Check the freewheel and limit-switch inputs on the drive — an input '
          'at zero will hold it here.',
      'If the command comes over the fieldbus, the drive sits here until the '
          'PLC sends a command.',
    ],
  ),
  4: Atv320Explanation(
    code: 4,
    mnemonic: 'RUN',
    label: 'Running',
    meaning: 'The motor is running, or a run command is present at zero '
        'speed reference.',
    severity: Atv320Severity.ok,
  ),
  5: Atv320Explanation(
    code: 5,
    mnemonic: 'ACC',
    label: 'Accelerating',
    meaning: 'Ramping up to the speed setpoint.',
    severity: Atv320Severity.ok,
  ),
  6: Atv320Explanation(
    code: 6,
    mnemonic: 'DEC',
    label: 'Decelerating',
    meaning: 'Ramping down to a stop or to a lower setpoint.',
    severity: Atv320Severity.ok,
  ),
  7: Atv320Explanation(
    code: 7,
    mnemonic: 'CLI',
    label: 'Current limit',
    meaning: 'The drive is capping the motor current to protect itself, so '
        'the belt will not reach its setpoint. Normally means the belt is '
        'overloaded or something is binding.',
    severity: Atv320Severity.warning,
    remedy: [
      'Look at the belt — check for a jam, an overloaded run or a seized '
          'roller.',
      'Check the size of the motor/drive/load for the job being run.',
      'If it is mechanically clear, have the current limit and motor '
          'settings checked against the motor plate.',
    ],
  ),
  8: Atv320Explanation(
    code: 8,
    mnemonic: 'FST',
    label: 'Fast stop',
    meaning: 'Stopping on the fast-stop ramp rather than the normal one.',
    severity: Atv320Severity.info,
    remedy: [
      'Check the input assigned to fast stop — like freewheel, it is active '
          'at zero, so a broken wire triggers it.',
    ],
  ),
  11: Atv320Explanation(
    code: 11,
    mnemonic: 'NLP',
    label: 'No mains voltage',
    meaning: 'The control electronics are powered, but the power section has '
        'no mains — the DC bus is not charged, so the motor cannot run.',
    severity: Atv320Severity.warning,
    remedy: [
      'Check the mains supply to the drive, its fuses and its breaker.',
      'Check the line contactor if one is fitted.',
    ],
  ),
  13: Atv320Explanation(
    code: 13,
    mnemonic: 'CTL',
    label: 'Controlled stop',
    meaning: 'Bringing the motor to a controlled stop, typically after the '
        'mains supply was lost.',
    severity: Atv320Severity.info,
  ),
  14: Atv320Explanation(
    code: 14,
    mnemonic: 'OBR',
    label: 'Adapted deceleration',
    meaning: 'The drive has stretched the deceleration ramp by itself to '
        'avoid tripping on DC bus overvoltage. The belt is taking longer to '
        'stop than its ramp asks for.',
    severity: Atv320Severity.warning,
    remedy: [
      'Increase the deceleration time so the drive does not have to.',
      'If the load is a driving one, a braking resistor may be needed.',
    ],
  ),
  15: Atv320Explanation(
    code: 15,
    mnemonic: 'SOC',
    label: 'Output cut',
    meaning: 'The output to the motor is cut and the drive is standing by.',
    severity: Atv320Severity.info,
  ),
  17: Atv320Explanation(
    code: 17,
    mnemonic: 'USA',
    label: 'Undervoltage warning',
    meaning: 'The supply has dropped below the warning threshold but not far '
        'enough to trip. If it keeps sagging the drive will fault on USF.',
    severity: Atv320Severity.warning,
    remedy: [
      'Check the supply voltage and look for what is loading it — a large '
          'motor starting on the same feed will do this.',
      'Check the mains connections and fuses for a poor joint.',
    ],
  ),
  18: Atv320Explanation(
    code: 18,
    mnemonic: 'TC',
    label: 'Factory test mode',
    meaning: 'The drive is in the manufacturer test mode. It will not run '
        'the line in this state.',
    severity: Atv320Severity.warning,
    remedy: ['Power the drive down and back up.'],
  ),
  19: Atv320Explanation(
    code: 19,
    mnemonic: 'ST',
    label: 'Self-test running',
    meaning: 'The drive is running its internal self-test.',
    severity: Atv320Severity.info,
    remedy: ['Wait for it to finish.'],
  ),
  20: Atv320Explanation(
    code: 20,
    mnemonic: 'FA',
    label: 'Self-test failed',
    meaning: 'The drive failed its own internal self-test.',
    severity: Atv320Severity.fault,
    remedy: [
      'Power the drive down and back up.',
      'If it fails again the drive needs replacing — contact Schneider '
          'Product Support.',
    ],
  ),
  21: Atv320Explanation(
    code: 21,
    mnemonic: 'OK',
    label: 'Self-test passed',
    meaning: 'The internal self-test completed successfully.',
    severity: Atv320Severity.ok,
  ),
  22: Atv320Explanation(
    code: 22,
    mnemonic: 'EP',
    label: 'EEPROM test error',
    meaning: 'The drive found a problem with its internal memory during the '
        'self-test.',
    severity: Atv320Severity.fault,
    remedy: [
      'Power the drive down and back up.',
      'If it persists, contact Schneider Product Support.',
    ],
  ),
  23: Atv320Explanation(
    code: 23,
    mnemonic: 'FLT',
    label: 'Faulted',
    meaning: 'The drive has tripped and stopped the motor. The Last fault '
        'row below says why.',
    severity: Atv320Severity.fault,
    remedy: [
      'Read the Last fault row — it names the trip and what clears it.',
      'Fix the cause first, then use Fault reset.',
    ],
  ),
  25: Atv320Explanation(
    code: 25,
    mnemonic: 'DCP',
    label: 'Firmware flashing',
    meaning: 'The drive firmware is being written. Do not remove power.',
    severity: Atv320Severity.warning,
    remedy: ['Leave it alone until it finishes.'],
  ),
  30: Atv320Explanation(
    code: 30,
    mnemonic: 'STO',
    label: 'Safe Torque Off',
    meaning: 'The safety circuit has removed torque from the motor. The belt '
        'cannot run until the safety chain is made again. Note that the DC '
        'bus is still live — STO removes torque, not power.',
    severity: Atv320Severity.warning,
    remedy: [
      'Check the guards, the safety gates and the emergency stops on this '
          'section.',
      'Reset the safety relay once the chain is made.',
      'If nothing is tripped, check the STO wiring — the STO input is fed '
          'from 24 V and drops out if that supply is lost.',
    ],
  ),
  35: Atv320Explanation(
    code: 35,
    mnemonic: 'IDLE',
    label: 'Energy saving',
    meaning: 'The drive has gone into its energy-saving idle mode.',
    severity: Atv320Severity.info,
  ),
  36: Atv320Explanation(
    code: 36,
    mnemonic: 'FWUP',
    label: 'Firmware update',
    meaning: 'A firmware update is in progress. Do not remove power.',
    severity: Atv320Severity.warning,
    remedy: ['Leave it alone until it finishes.'],
  ),
  37: Atv320Explanation(
    code: 37,
    mnemonic: 'URA',
    label: 'Mains undervoltage',
    meaning: 'The supply to the drive input stage is too low.',
    severity: Atv320Severity.warning,
    remedy: ['Check the supply voltage and the mains connections.'],
  ),
  // Not an ATV320 state — the PLC substitutes this when it cannot read the
  // drive at all. FB_ATV320 sets it together with a CNF last-fault whenever
  // the EtherCAT link is down or the slave is not at OP, so the pair has to
  // be explained as one thing (see the CNF entry below).
  99: Atv320Explanation(
    code: 99,
    mnemonic: 'LOST',
    label: 'No link to drive',
    meaning: 'The PLC cannot reach this drive over EtherCAT, so nothing on '
        'this pane is live. The drive itself may be perfectly healthy — this '
        'says the PLC cannot see it.',
    severity: Atv320Severity.fault,
    remedy: [
      'Check that the drive is powered up.',
      'Check the EtherCAT cabling in and out of the drive, and any device '
          'upstream of it — a break takes out everything downstream too.',
      'Check whether other drives in the same cabinet are also showing no '
          'link; if they are, the problem is upstream.',
    ],
  ),
};

// ---------------------------------------------------------------------------
// LFT — last fault (`lft_e`)
// ---------------------------------------------------------------------------

/// Decodes `p_stat_LastFault` (LFT).
///
/// Codes present in `lft_e` but not documented for the ATV320 in NVE41295
/// come back with `documented: false` and no invented remedy.
Atv320Explanation atv320Fault(int code) =>
    _faults[code] ?? _familyFaults[code] ?? _unknown(code, 'fault code');

/// Faults NVE41295 documents for the ATV320, with the manual's own probable
/// cause and remedy. [Atv320Clearing] follows the manual's three tables:
/// "requires a power reset" (p.309), "cleared with the automatic restart
/// function" (p.311) and "cleared as soon as their cause disappears" (p.314).
const Map<int, Atv320Explanation> _faults = {
  0: Atv320Explanation(
    code: 0,
    mnemonic: 'NOF',
    label: 'No fault',
    meaning: 'The drive has not recorded a fault.',
    severity: Atv320Severity.ok,
  ),
  2: Atv320Explanation(
    code: 2,
    mnemonic: 'EEF1',
    label: 'Control EEPROM error',
    meaning: 'Internal memory fault on the control block.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the electrical environment — this is often an EMC problem.',
      'Power down, reset, and if needed return the drive to factory settings '
          'and re-load its configuration.',
    ],
  ),
  3: Atv320Explanation(
    code: 3,
    mnemonic: 'CFF',
    label: 'Incorrect configuration',
    meaning: 'An option card was changed or removed, the control block was '
        'swapped for one configured on a different rating, or the stored '
        'configuration is inconsistent.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.selfClears,
    remedy: [
      'Check that no card has been disturbed.',
      'If a card or control block was changed on purpose, confirm it on the '
          'keypad — this restores factory settings for the affected group.',
      'Otherwise reload the backup configuration.',
    ],
  ),
  4: Atv320Explanation(
    code: 4,
    mnemonic: 'CFI',
    label: 'Invalid configuration',
    meaning: 'The configuration loaded into the drive over the bus is not '
        'consistent.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.selfClears,
    remedy: [
      'Check the configuration that was loaded previously.',
      'Load a configuration that matches this drive.',
    ],
  ),
  5: Atv320Explanation(
    code: 5,
    mnemonic: 'SLF1',
    label: 'Modbus communication lost',
    meaning: 'Communication on the drive\'s Modbus port was interrupted.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the Modbus wiring and termination.',
      'Check the configured time-out.',
    ],
  ),
  6: Atv320Explanation(
    code: 6,
    mnemonic: 'ILF',
    label: 'Option card link lost',
    meaning: 'Communication between the drive and its option card was '
        'interrupted.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the electrical environment (EMC).',
      'Check that the option card is seated properly.',
      'Replace the option card if it persists.',
    ],
  ),
  // The PLC also writes this code itself: FB_ATV320 forces LastFault = CNF
  // and State = LOST whenever the EtherCAT link is down or the slave is not
  // at OP. So on this line CNF usually means "the PLC lost the drive", not
  // "the drive lost its fieldbus" — worth saying, or an electrician goes
  // looking inside a drive that is fine.
  7: Atv320Explanation(
    code: 7,
    mnemonic: 'CNF',
    label: 'Fieldbus communication lost',
    meaning: 'The fieldbus link to this drive was interrupted. On this line '
        'the PLC also records CNF whenever it cannot reach the drive over '
        'EtherCAT at all — if the state above reads "No link to drive", this '
        'is that, and not a fault inside the drive.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check that the drive is powered and its EtherCAT cables are sound, '
          'including the device feeding it.',
      'Check the electrical environment (EMC) and the bus time-out.',
      'Replace the option card if the drive is reachable but keeps dropping.',
    ],
  ),
  8: Atv320Explanation(
    code: 8,
    mnemonic: 'EPF1',
    label: 'External fault (input)',
    meaning: 'Something outside the drive tripped it through a digital input '
        'or a control bit.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Find the device wired to that input — that is what tripped, not the '
          'drive.',
      'Clear it there, then reset.',
    ],
  ),
  9: Atv320Explanation(
    code: 9,
    mnemonic: 'OCF',
    label: 'Overcurrent',
    meaning: 'The motor drew more current than the drive allows. On a belt '
        'this is usually a jam, a seized roller, or a load the drive cannot '
        'accelerate on its ramp.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the belt for a jam or an obstruction before resetting.',
      'Check the state of the mechanism — bearings, rollers, scrapers.',
      'Check the size of the motor/drive/load for what is being run.',
      'If it is mechanically clear, have the ramp and motor settings '
          'checked; increasing the acceleration time or the switching '
          'frequency, or lowering the current limit, may be needed.',
    ],
  ),
  10: Atv320Explanation(
    code: 10,
    mnemonic: 'CRF1',
    label: 'Precharge circuit fault',
    meaning: 'The charging relay or the charging resistor in the drive is '
        'faulty.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Power the drive down and back up.',
      'Check the internal connections.',
      'Contact Schneider Product Support if it persists.',
    ],
  ),
  13: Atv320Explanation(
    code: 13,
    mnemonic: 'LFF2',
    label: 'AI2 4-20 mA signal lost',
    meaning: 'The 4-20 mA reference on analog input AI2 dropped out.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the wiring on analog input AI2 and the device driving it.',
    ],
  ),
  16: Atv320Explanation(
    code: 16,
    mnemonic: 'OHF',
    label: 'Drive overheating',
    meaning: 'The drive itself is too hot.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Let the drive cool down before restarting.',
      'Check the cabinet ventilation and clean the drive\'s fan and heatsink '
          '— fish plants blind them quickly.',
      'Check the ambient temperature and the motor load.',
    ],
  ),
  17: Atv320Explanation(
    code: 17,
    mnemonic: 'OLF',
    label: 'Motor overload',
    meaning: 'The motor drew too much current for too long and the drive\'s '
        'thermal model tripped it.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Let the motor cool down before restarting.',
      'Check what the belt is being asked to move, and check for binding.',
      'Check the motor thermal protection setting against the motor plate.',
    ],
  ),
  18: Atv320Explanation(
    code: 18,
    mnemonic: 'OBF',
    label: 'DC bus overvoltage (braking)',
    meaning: 'Braking too hard, or a driving load pushing the motor, sent '
        'the DC bus over its limit.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Increase the deceleration time.',
      'Enable the adapted-deceleration function if the application allows.',
      'Fit a braking resistor if the load drives the motor.',
      'Check the supply voltage is not too high.',
    ],
  ),
  19: Atv320Explanation(
    code: 19,
    mnemonic: 'OSF',
    label: 'Mains overvoltage',
    meaning: 'The supply voltage is too high, or the mains is disturbed.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: ['Check the supply voltage.'],
  ),
  20: Atv320Explanation(
    code: 20,
    mnemonic: 'OPF1',
    label: 'One motor phase lost',
    meaning: 'One of the three phases between the drive and the motor is '
        'missing.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the connections from the drive to the motor, both ends.',
      'Check the motor terminal box — a loose or corroded joint does this.',
    ],
  ),
  21: Atv320Explanation(
    code: 21,
    mnemonic: 'PHF',
    label: 'Input phase loss',
    meaning: 'The drive is missing a supply phase, has a blown fuse, or is '
        'running an unbalanced load. Only detected when the drive is loaded.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.selfClears,
    remedy: [
      'Check the power connections and the fuses feeding the drive.',
      'Check that a 3-phase drive is not sitting on a single-phase supply.',
    ],
  ),
  22: Atv320Explanation(
    code: 22,
    mnemonic: 'USF',
    label: 'Undervoltage',
    meaning: 'The supply is too low, or dipped transiently — often when '
        'something large starts on the same feed.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.selfClears,
    remedy: [
      'Check the supply voltage at the drive.',
      'Look for what else starts at the same moment.',
      'Have the undervoltage management settings checked if the dips are '
          'unavoidable.',
    ],
  ),
  23: Atv320Explanation(
    code: 23,
    mnemonic: 'SCF1',
    label: 'Motor short circuit',
    meaning: 'A short circuit or an earth fault at the drive output.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Do not simply reset — check the cables from the drive to the motor '
          'and the motor insulation first.',
      'Water in a motor terminal box or a chafed cable is the usual cause on '
          'a wet line.',
      'If the cabling is sound, reducing the switching frequency or fitting '
          'motor chokes may be needed.',
    ],
  ),
  24: Atv320Explanation(
    code: 24,
    mnemonic: 'SOF',
    label: 'Overspeed',
    meaning: 'The motor ran faster than allowed — instability, or a load '
        'driving the motor.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the motor, gain and stability parameters.',
      'Check the size of the motor/drive/load.',
      'Fit a braking resistor if the load drives the motor.',
    ],
  ),
  25: Atv320Explanation(
    code: 25,
    mnemonic: 'TNF',
    label: 'Auto-tuning failed',
    meaning: 'The drive could not measure the motor — usually because the '
        'motor was not connected, was turning, or does not suit the drive.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the motor is connected and stopped, then tune again.',
      'If an output contactor is fitted, it must be closed during tuning.',
      'Check that the motor and drive ratings match.',
    ],
  ),
  26: Atv320Explanation(
    code: 26,
    mnemonic: 'INF1',
    label: 'Internal error 1 — rating',
    meaning: 'The power card in the drive is not the one it has stored.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: ['Check the reference of the power card.'],
  ),
  27: Atv320Explanation(
    code: 27,
    mnemonic: 'INF2',
    label: 'Internal error 2 — power board',
    meaning: 'The power card is incompatible with the control block.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: ['Check the reference of the power card and its compatibility.'],
  ),
  28: Atv320Explanation(
    code: 28,
    mnemonic: 'INF3',
    label: 'Internal error 3 — internal link',
    meaning: 'Communication between the drive\'s internal cards was '
        'interrupted.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the internal connections.',
      'Contact Schneider Product Support.',
    ],
  ),
  29: Atv320Explanation(
    code: 29,
    mnemonic: 'INF4',
    label: 'Internal error 4 — manufacturing data',
    meaning: 'The drive\'s internal calibration data is inconsistent.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: ['The drive needs recalibrating by Schneider Product Support.'],
  ),
  30: Atv320Explanation(
    code: 30,
    mnemonic: 'EEF2',
    label: 'Power EEPROM error',
    meaning: 'Internal memory fault on the power card.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: ['Contact Schneider Product Support.'],
  ),
  32: Atv320Explanation(
    code: 32,
    mnemonic: 'SCF3',
    label: 'Earth short circuit',
    meaning: 'Significant earth leakage current at the drive output.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the cables from the drive to the motor and the motor '
          'insulation before resetting — water ingress is the usual cause.',
      'Reducing the switching frequency or fitting motor chokes may help if '
          'the insulation is sound.',
    ],
  ),
  33: Atv320Explanation(
    code: 33,
    mnemonic: 'OPF2',
    label: 'All motor phases lost',
    meaning: 'The motor is not connected, its power is very low, or an '
        'output contactor is open.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the connections from the drive to the motor.',
      'If an output contactor is used, the drive must be told about it.',
      'Check the motor rating and IR compensation settings, and re-tune.',
    ],
  ),
  34: Atv320Explanation(
    code: 34,
    mnemonic: 'COF',
    label: 'CANopen communication lost',
    meaning: 'Communication on the CANopen bus was interrupted.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the bus wiring and termination.',
      'Check the configured time-out.',
    ],
  ),
  38: Atv320Explanation(
    code: 38,
    mnemonic: 'EPF2',
    label: 'External fault (fieldbus)',
    meaning: 'Something on the network tripped the drive.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: ['Find what sent the trip on the network, clear it, then reset.'],
  ),
  41: Atv320Explanation(
    code: 41,
    mnemonic: 'BRF',
    label: 'Brake feedback',
    meaning: 'The brake feedback contact does not agree with the brake '
        'command, or the brake is not stopping the motor quickly enough.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the brake feedback circuit and the brake control circuit.',
      'Check the mechanical state of the brake and its linings.',
    ],
  ),
  42: Atv320Explanation(
    code: 42,
    mnemonic: 'SLF2',
    label: 'PC software link lost',
    meaning: 'Communication with the PC configuration software was '
        'interrupted.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: ['Check the PC connecting cable and the time-out.'],
  ),
  44: Atv320Explanation(
    code: 44,
    mnemonic: 'SSF',
    label: 'Torque / current limit',
    meaning: 'The drive hit its torque or current limit and was configured '
        'to trip on it. Usually mechanical.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the belt for anything binding or jammed.',
      'Have the torque-limit settings reviewed if the machine is clear.',
    ],
  ),
  45: Atv320Explanation(
    code: 45,
    mnemonic: 'SLF3',
    label: 'Keypad link lost',
    meaning: 'Communication with the graphic or remote display terminal was '
        'interrupted.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: ['Check the terminal connection and the time-out.'],
  ),
  49: Atv320Explanation(
    code: 49,
    mnemonic: 'PTFL',
    label: 'PTC probe fault',
    meaning: 'The motor PTC probe on input LI6 is open circuit or shorted.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the PTC probe and the wiring between the motor and the drive.',
    ],
  ),
  51: Atv320Explanation(
    code: 51,
    mnemonic: 'INF9',
    label: 'Internal error 9 — current measurement',
    meaning: 'The drive\'s current measurements are wrong.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'The current sensors or power card need replacing — contact Schneider '
          'Product Support.',
    ],
  ),
  52: Atv320Explanation(
    code: 52,
    mnemonic: 'INFA',
    label: 'Internal error 10 — mains circuit',
    meaning: 'The drive input stage is not operating correctly.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: ['Contact Schneider Product Support.'],
  ),
  53: Atv320Explanation(
    code: 53,
    mnemonic: 'INFB',
    label: 'Internal error 11 — temperature sensor',
    meaning: 'The drive\'s own temperature sensor is not working.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'The sensor needs replacing — contact Schneider Product Support.',
    ],
  ),
  54: Atv320Explanation(
    code: 54,
    mnemonic: 'TJF',
    label: 'IGBT overheating',
    meaning: 'The drive\'s output stage overheated.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Let it cool before restarting.',
      'Check the size of the load/motor/drive.',
      'Reducing the switching frequency may be needed.',
    ],
  ),
  55: Atv320Explanation(
    code: 55,
    mnemonic: 'SCF4',
    label: 'IGBT short circuit',
    meaning: 'A power component inside the drive has failed.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: ['Contact Schneider Product Support — the drive needs attention.'],
  ),
  56: Atv320Explanation(
    code: 56,
    mnemonic: 'SCF5',
    label: 'Motor short circuit',
    meaning: 'A short circuit at the drive output, caught while loading the '
        'output stage.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the cables from the drive to the motor and the motor '
          'insulation.',
      'Contact Schneider Product Support if the cabling is sound.',
    ],
  ),
  58: Atv320Explanation(
    code: 58,
    mnemonic: 'FCF1',
    label: 'Output contactor stuck closed',
    meaning: 'The output contactor stayed closed when it should have opened.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the contactor and its wiring.',
      'Check the feedback circuit.',
    ],
  ),
  59: Atv320Explanation(
    code: 59,
    mnemonic: 'FCF2',
    label: 'Output contactor stuck open',
    meaning: 'The output contactor stayed open when it should have closed.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the contactor and its wiring.',
      'Check the feedback circuit.',
    ],
  ),
  64: Atv320Explanation(
    code: 64,
    mnemonic: 'LCF',
    label: 'Input contactor fault',
    meaning: 'The drive did not power up within the configured mains '
        'time-out.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the line contactor and its wiring.',
      'Check the supply / contactor / drive connections and the time-out.',
    ],
  ),
  68: Atv320Explanation(
    code: 68,
    mnemonic: 'INF6',
    label: 'Internal error 6 — option',
    meaning: 'The option fitted in the drive is not recognised.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the reference and compatibility of the option.',
      'Check that it is properly inserted.',
    ],
  ),
  69: Atv320Explanation(
    code: 69,
    mnemonic: 'INFE',
    label: 'Internal error 14 — CPU',
    meaning: 'The drive\'s internal microprocessor faulted.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Power down and reset.',
      'Contact Schneider Product Support if it persists.',
    ],
  ),
  71: Atv320Explanation(
    code: 71,
    mnemonic: 'LFF3',
    label: 'AI3 4-20 mA signal lost',
    meaning: 'The 4-20 mA reference on analog input AI3 dropped out.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the wiring on analog input AI3 and the device driving it.',
    ],
  ),
  72: Atv320Explanation(
    code: 72,
    mnemonic: 'LFF4',
    label: 'AI4 4-20 mA signal lost',
    meaning: 'The 4-20 mA reference on analog input AI4 dropped out.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the wiring on analog input AI4 and the device driving it.',
    ],
  ),
  73: Atv320Explanation(
    code: 73,
    mnemonic: 'HCF',
    label: 'Card pairing fault',
    meaning: 'Card pairing is configured and a card in the drive has been '
        'changed.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.selfClears,
    remedy: [
      'Refit the original card if the change was not intended.',
      'If it was intended, confirm the new configuration with the pairing '
          'password.',
    ],
  ),
  77: Atv320Explanation(
    code: 77,
    mnemonic: 'CFI2',
    label: 'Configuration transfer error',
    meaning: 'A configuration transfer into the drive did not complete '
        'correctly.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.selfClears,
    remedy: ['Check and re-load a configuration that matches this drive.'],
  ),
  79: Atv320Explanation(
    code: 79,
    mnemonic: 'LFF5',
    label: 'AI5 4-20 mA signal lost',
    meaning: 'The 4-20 mA reference on analog input AI5 dropped out.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the wiring on analog input AI5 and the device driving it.',
    ],
  ),
  99: Atv320Explanation(
    code: 99,
    mnemonic: 'CSF',
    label: 'Channel switching fault',
    meaning: 'The drive was told to switch to a command or reference channel '
        'that is not valid.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.selfClears,
    remedy: ['Check the channel-switching function parameters.'],
  ),
  100: Atv320Explanation(
    code: 100,
    mnemonic: 'ULF',
    label: 'Process underload',
    meaning: 'The motor is doing less work than the underload monitor '
        'expects — on a belt, often a broken or slipping drive coupling, or '
        'simply an empty line.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the belt is still coupled to the motor and has not shed a chain '
          'or a belt.',
      'Check the underload monitoring settings if the line is simply '
          'running empty.',
    ],
  ),
  101: Atv320Explanation(
    code: 101,
    mnemonic: 'OLC',
    label: 'Process overload',
    meaning: 'The motor is doing more work than the overload monitor allows '
        '— the belt is loaded beyond what it is set up for, or something is '
        'dragging.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Find and clear the cause of the overload before resetting.',
      'Check the process overload settings if the load is legitimate.',
    ],
  ),
  105: Atv320Explanation(
    code: 105,
    mnemonic: 'ASF',
    label: 'Angle measurement error',
    meaning: 'The phase-shift angle measurement failed — a motor phase is '
        'disconnected, or the motor inductance is too high for the drive.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the motor phases and the maximum current the drive allows.',
    ],
  ),
  106: Atv320Explanation(
    code: 106,
    mnemonic: 'LFF1',
    label: 'AI1 4-20 mA signal lost',
    meaning: 'The 4-20 mA reference on analog input AI1 dropped out.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.faultReset,
    remedy: [
      'Check the wiring on analog input AI1 and the device driving it.',
    ],
  ),
  107: Atv320Explanation(
    code: 107,
    mnemonic: 'SAFF',
    label: 'Safety function fault',
    meaning: 'An integrated safety function tripped — debounce time '
        'exceeded, a threshold exceeded, or a wrong configuration.',
    severity: Atv320Severity.fault,
    clearing: Atv320Clearing.powerCycle,
    remedy: [
      'Check the safety function configuration against the ATV320 Integrated '
          'Safety Functions manual.',
      'Contact Schneider Product Support if the configuration is correct.',
    ],
  ),
};

/// Codes that exist in `lft_e` because the enum covers the whole Altivar
/// range, but that NVE41295 does not document for the ATV320 — pump, cabinet,
/// active-front-end and multi-drive faults, plus internal error numbers with
/// no published remedy.
///
/// The names are the PLC enum's own; the advice stops at "note the code",
/// because inventing a remedy for a fault this drive should never raise is
/// worse than admitting we do not have one.
final Map<int, Atv320Explanation> _familyFaults = Map.unmodifiable({
  for (final e in <(int, String, String)>[
    (15, 'IHF', 'Input overheating'),
    (37, 'INF7', 'Internal error 7 — initialisation'),
    (40, 'INF8', 'Internal error 8 — switching supply'),
    (60, 'INFC', 'Internal error 12 — internal current supply'),
    (80, 'FFDF', 'Fan feedback error'),
    (81, 'MOF', 'Module overheat'),
    (110, 'TH2F', 'AI2 thermal level error'),
    (111, 'T2CF', 'AI2 thermal sensor error'),
    (112, 'TH3F', 'AI3 thermal level error'),
    (113, 'T3CF', 'AI3 thermal sensor error'),
    (114, 'PCPF', 'Pump cycle start error'),
    (115, 'OPLF', 'Outlet pressure low'),
    (116, 'HFPF', 'High flow error'),
    (117, 'IPPF', 'Inlet pressure error'),
    (119, 'PLFF', 'Pump low flow error'),
    (120, 'TH4F', 'AI4 thermal level error'),
    (121, 'T4CF', 'AI4 thermal sensor error'),
    (122, 'TH5F', 'AI5 thermal level error'),
    (123, 'T5CF', 'AI5 thermal sensor error'),
    (124, 'JAMF', 'Anti-jam error'),
    (125, 'OPHF', 'Outlet pressure high'),
    (126, 'DRYF', 'Dry run error'),
    (127, 'PFMF', 'PID feedback error'),
    (128, 'PGLF', 'Program loading error'),
    (129, 'PGRF', 'Program running error'),
    (130, 'MPLF', 'Lead pump error'),
    (131, 'LCLF', 'Low level error'),
    (132, 'LCHF', 'High level error'),
    (142, 'INFG', 'Internal error 16 — IO module relay'),
    (143, 'INFH', 'Internal error 17 — IO module standard'),
    (144, 'INF0', 'Internal error 0 — IPC'),
    (146, 'INFD', 'Internal error 13 — differential current'),
    (148, 'STF', 'Motor stall error'),
    (149, 'INFL', 'Internal error 21 — real-time clock'),
    (150, 'ETHF', 'Embedded Ethernet communication lost'),
    (151, 'INFF', 'Internal error 15 — flash'),
    (152, 'FWER', 'Firmware update error'),
    (153, 'INFM', 'Internal error 22 — embedded Ethernet'),
    (154, 'INFP', 'Internal error 25 — control board incompatibility'),
    (155, 'INFK', 'Internal error 20 — option interface board'),
    (157, 'INFR', 'Internal error 27 — diagnostics CPLD'),
    (158, 'INFN', 'Internal error 23 — module link'),
    (159, 'SCF6', 'Active front end short circuit'),
    (160, 'OBF2', 'Active front end bus unbalancing'),
    (161, 'INFS', 'Internal error 28 — active front end'),
    (162, 'IFA', 'Monitoring circuit A error'),
    (163, 'IFB', 'Monitoring circuit B error'),
    (164, 'IFC', 'Monitoring circuit C error'),
    (165, 'IFD', 'Monitoring circuit D error'),
    (166, 'CFA', 'Cabinet circuit A error'),
    (167, 'CFB', 'Cabinet circuit B error'),
    (168, 'CFC', 'Cabinet circuit C error'),
    (169, 'TFA', 'Motor winding A error'),
    (170, 'TFB', 'Motor winding B error'),
    (171, 'TFC', 'Motor bearing A error'),
    (172, 'TFD', 'Motor bearing B error'),
    (173, 'CHF', 'Cabinet overheat error'),
    (174, 'URF', 'Active front end mains undervoltage'),
    (175, 'INFV', 'Internal error 31 — missing brick'),
    (176, 'INFT', 'Internal error 29 — inverter'),
    (177, 'INFU', 'Internal error 30 — rectifier'),
    (179, 'TJF2', 'Active front end IGBT overheat'),
    (180, 'CRF3', 'Active front end contactor feedback error'),
    (181, 'CFI3', 'Pre-settings transfer error'),
    (182, 'CBF', 'Circuit breaker error'),
    (186, 'MDLF', 'MultiDrive link error'),
    (190, 'MPDF', 'Multipump device error'),
    (191, 'ACF1', 'Active front end modulation rate error'),
    (192, 'ACF2', 'Active front end current control error'),
    (193, 'MFF', 'Mains frequency out of range'),
    (200, 'FDR1', 'FDR embedded Ethernet error'),
    (201, 'FDR2', 'FDR Ethernet module error'),
    (203, 'P24C', 'Cabinet I/O 24 V missing'),
    (206, 'DCRE', 'DC bus ripple error'),
    (208, 'IDLF', 'Idle mode exit error'),
    (211, 'SPFC', 'Security files corrupt'),
  ])
    e.$1: Atv320Explanation(
      code: e.$1,
      mnemonic: e.$2,
      label: e.$3,
      meaning: 'The drive reported ${e.$2}. This code belongs to the wider '
          'Altivar range and is not documented for the ATV320, so there is no '
          'published cause or remedy for it here.',
      severity: Atv320Severity.fault,
      documented: false,
      remedy: [
        'Note the code and read the drive keypad\'s DIAGNOSTICS menu, which '
            'shows the fault in plain text.',
        'Power the drive down and back up once the line is safe.',
        'Contact Schneider Product Support with the code if it returns.',
      ],
    ),
});

/// A value outside both `hmis_e` and `lft_e`. Reported honestly rather than
/// mapped onto the nearest known code.
Atv320Explanation _unknown(int code, String what) => Atv320Explanation(
      code: code,
      mnemonic: '$code',
      label: 'Unrecognised code $code',
      meaning: 'The drive published a $what the HMI does not know. Either '
          'the drive firmware is newer than the PLC\'s table, or the value '
          'is not a $what at all.',
      severity: Atv320Severity.warning,
      documented: false,
      remedy: [
        'Read the drive keypad\'s DIAGNOSTICS menu, which shows the state in '
            'plain text.',
        'Note the code — it is needed to extend the HMI\'s table.',
      ],
    );
