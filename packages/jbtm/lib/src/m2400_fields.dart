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
  // --- Confirmed from real device data (HIGH confidence) ---
  weight(1, 'Weight', FieldType.decimal),
  unit(2, 'Unit', FieldType.string),
  siWeight(77, 'SI Weight', FieldType.string),

  // --- Device-observed provisional fields ---
  field6(6, 'Field 6', FieldType.integer),
  field11(11, 'Field 11', FieldType.integer),
  field59(59, 'Field 59', FieldType.decimal),
  field78(78, 'Field 78', FieldType.decimal),
  field79(79, 'Field 79', FieldType.decimal),
  field80(80, 'Field 80', FieldType.integer),
  field81(81, 'Field 81', FieldType.string),

  // --- From requirements, IDs unconfirmed (placeholder = 0) ---
  status(0, 'Weigher Status', FieldType.integer),
  devId(0, 'Device ID', FieldType.integer),
  output(0, 'Output', FieldType.integer),
  material(0, 'Material', FieldType.string),
  wQuality(0, 'Weight Quality', FieldType.integer),
  wCount(0, 'Weight Count', FieldType.integer),
  length(0, 'Length', FieldType.decimal),
  batchId(0, 'Batch ID', FieldType.string),
  pieces(0, 'Pieces', FieldType.integer),
  msgId(0, 'Message ID', FieldType.integer),
  regCmd(0, 'Register Command', FieldType.string),
  key(0, 'Key', FieldType.string),
  devType(0, 'Device Type', FieldType.string),
  devProg(0, 'Device Program', FieldType.string),
  exId(0, 'External ID', FieldType.string),
  position(0, 'Position', FieldType.integer),
  errText(0, 'Error Text', FieldType.string),
  buttonId(0, 'Button ID', FieldType.integer),
  idFamily(0, 'ID Family', FieldType.string),
  tare(0, 'Tare', FieldType.decimal),
  barcode(0, 'Barcode', FieldType.string),
  saddles(0, 'Saddles', FieldType.integer),
  nominal(0, 'Nominal', FieldType.decimal),
  target(0, 'Target', FieldType.decimal),
  fGiveaway(0, 'Fixed Giveaway', FieldType.decimal),
  vGiveaway(0, 'Variable Giveaway', FieldType.decimal),
  tareType(0, 'Tare Type', FieldType.string),
  serialNumber(0, 'Serial Number', FieldType.string),
  stdDevA(0, 'Std Deviation A', FieldType.decimal),
  resultCode(0, 'Result Code', FieldType.integer),
  date(0, 'Date', FieldType.date),
  time(0, 'Time', FieldType.time),
  timeMs(0, 'Time Milliseconds', FieldType.timeMs),
  scaleRange(0, 'Scale Range', FieldType.string),
  weighingStatus(0, 'Weighing Status', FieldType.integer),
  programId(0, 'Program ID', FieldType.integer),
  programName(0, 'Program Name', FieldType.string),
  minWeight(0, 'Min Weight', FieldType.decimal),
  maxWeight(0, 'Max Weight', FieldType.decimal),
  alibi(0, 'Alibi', FieldType.string),
  division(0, 'Division', FieldType.decimal),
  recordId(0, 'ID', FieldType.integer),
  rejectReason(0, 'Reject Reason', FieldType.string),
  originLabel(0, 'Origin Label', FieldType.string),
  tareDevice(0, 'Tare Device', FieldType.decimal),
  tareAlibi(0, 'Tare Alibi', FieldType.string),
  packId(0, 'Pack ID', FieldType.string),
  checksum(0, 'Checksum', FieldType.string),
  alibiText(0, 'Alibi Text', FieldType.string),
  beltUsage(0, 'Belt Usage', FieldType.percentage),
  eventNo(0, 'Event Number', FieldType.integer),
  deltaTime(0, 'Delta Time', FieldType.decimal),
  deltaWeight(0, 'Delta Weight', FieldType.decimal),
  throughput(0, 'Throughput', FieldType.decimal),
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
    M2400Field.field6,
    M2400Field.field11,
    M2400Field.field59,
    M2400Field.field78,
    M2400Field.field79,
    M2400Field.field80,
    M2400Field.field81,
  },
};
