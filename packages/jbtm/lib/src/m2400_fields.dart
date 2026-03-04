import 'package:jbtm/src/m2400.dart';

/// The Dart type a field value should be parsed to.
enum FieldType {
  /// Numeric weight/measurement values -> double
  decimal,

  /// Integer IDs, counts, status codes -> int
  integer,

  /// Unit strings, mode strings, text -> String (no parsing needed)
  string,

  /// Percentage values (0-100) -> double
  percentage,

  /// Date string -> used with time/timeMs for DateTime construction
  date,

  /// Time string -> used with date/timeMs for DateTime construction
  time,

  /// Milliseconds component -> used with date/time for DateTime construction
  timeMs,
}

/// Known M2400 field types with their numeric protocol IDs and parse metadata.
///
/// Field IDs with value 0 are defined by requirements but not yet confirmed
/// against real device data. They will not match via [fromId].
///
/// Device-observed fields with provisional names (field6, field11, etc.) are
/// matchable via [fromId] and will be renamed when protocol docs confirm
/// their meaning.
enum M2400Field {
  weight(1, 'Weight', FieldType.decimal),
  unit(2, 'Unit', FieldType.string),
  siWeight(3, 'SI Weight', FieldType.string),
  output(4, 'Output', FieldType.integer),
  material(6, 'Material', FieldType.string),
  wQuality(7, 'Weight Quality', FieldType.integer),
  wCount(8, 'Weight Count', FieldType.integer),
  length(9, 'Length', FieldType.decimal),
  batchId(10, 'Batch ID', FieldType.string),
  status(11, 'Status', FieldType.integer),
  pieces(12, 'Pieces', FieldType.integer),
  msgId(17, 'Message ID', FieldType.integer),
  regCmd(18, 'Register Command', FieldType.string),
  key(19, 'Key', FieldType.string),
  devId(21, 'Device ID', FieldType.integer),
  devType(22, 'Device Type', FieldType.string),
  devProg(23, 'Device Program', FieldType.string),
  exId(26, 'External ID', FieldType.string),
  position(27, 'Position', FieldType.integer),
  errText(33, 'Error Text', FieldType.string),
  buttonId(55, 'Button ID', FieldType.integer),
  idFamily(56, 'ID Family', FieldType.string),
  tare(59, 'Tare', FieldType.decimal),
  barcode(61, 'Barcode', FieldType.string),
  saddles(76, 'Saddles', FieldType.integer),
  nominal(77, 'Nominal', FieldType.decimal),
  target(78, 'Target', FieldType.decimal),
  fGiveaway(79, 'Fixed Giveaway', FieldType.decimal),
  vGiveaway(80, 'Variable Giveaway', FieldType.decimal),
  tareType(81, 'Tare Type', FieldType.string),
  serialNumber(101, 'Serial Number', FieldType.string),
  stdDevA(111, 'Std Deviation A', FieldType.decimal),
  resultCode(117, 'Result Code', FieldType.integer),
  date(121, 'Date', FieldType.date),
  time(122, 'Time', FieldType.time),
  timeMs(123, 'Time (ms)', FieldType.timeMs),
  scaleRange(133, 'Scale Range', FieldType.string),
  weighingStatus(174, 'Weighing Status', FieldType.integer),
  programId(257, 'Program ID', FieldType.integer),
  programName(258, 'Program Name', FieldType.string),
  minWeight(334, 'Min Weight', FieldType.decimal),
  maxWeight(335, 'Max Weight', FieldType.decimal),
  alibi(345, 'Alibi', FieldType.string),
  division(390, 'Division', FieldType.decimal),
  recordId(400, 'ID', FieldType.integer),
  rejectReason(405, 'Reject Reason', FieldType.string),
  originLabel(501, 'Origin Label', FieldType.string),
  tareDevice(533, 'Tare Device', FieldType.decimal),
  tareAlibi(534, 'Tare Alibi', FieldType.string),
  packId(1040, 'Pack ID', FieldType.string),
  checksum(1047, 'Checksum', FieldType.string),
  alibiText(1137, 'Alibi Text', FieldType.string),
  ;

  final int id;
  final String displayName;
  final FieldType fieldType;

  const M2400Field(this.id, this.displayName, this.fieldType);

  /// Look up field by numeric ID. Returns null for unknown IDs.
  /// Fields with id <= 0 are placeholders and cannot be matched.
  static M2400Field? fromId(int id) {
    if (id <= 0) return null;
    for (final field in values) {
      if (field.id == id) return field;
    }
    return null;
  }
}

/// Weigher status codes from FLD_STATUS / FLD_WEIGHING_STATUS.
enum WeigherStatus {
  bad(0, 'Bad'),
  r1(1, 'Range 1'),
  r2(2, 'Range 2'),
  badDeny(10, 'Bad - Denied'),
  badStddev(11, 'Bad - Std Dev'),
  badAlibi(12, 'Bad - Alibi'),
  badUnexpect(13, 'Bad - Unexpected'),
  badUnder(14, 'Bad - Underweight'),
  badOver(15, 'Bad - Overweight'),
  unknown(-1, 'Unknown'),
  ;

  final int code;
  final String displayName;

  const WeigherStatus(this.code, this.displayName);

  /// Look up status by numeric code. Returns [unknown] for undefined codes.
  static WeigherStatus fromCode(int code) {
    for (final status in values) {
      if (status.code == code && status != unknown) return status;
    }
    return unknown;
  }
}

/// Fields typically present in each record type.
/// Based on real device data captures.
const Map<M2400RecordType, Set<M2400Field>> expectedFields = {
  M2400RecordType.recStat: {
    M2400Field.weight,
    M2400Field.unit,
  },
  M2400RecordType.recBatch: {
    M2400Field.weight,
    M2400Field.unit,
    M2400Field.siWeight,
    M2400Field.material,
    M2400Field.status,
    M2400Field.tare,
    M2400Field.target,
    M2400Field.fGiveaway,
    M2400Field.vGiveaway,
    M2400Field.tareType,
  },
};
