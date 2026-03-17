/// Web stub for package:jbtm/src/m2400_fields.dart

// ignore_for_file: constant_identifier_names

enum FieldType { string, numeric, unknown }

enum M2400Field {
  weight(1, 'Weight', FieldType.numeric),
  unit(2, 'Unit', FieldType.string),
  siWeight(3, 'SI Weight', FieldType.numeric),
  output(4, 'Output', FieldType.string),
  material(5, 'Material', FieldType.string),
  wQuality(6, 'Quality', FieldType.string),
  wCount(7, 'Count', FieldType.numeric),
  length(8, 'Length', FieldType.numeric),
  batchId(9, 'Batch ID', FieldType.string),
  status(10, 'Status', FieldType.string),
  pieces(11, 'Pieces', FieldType.numeric),
  msgId(12, 'Msg ID', FieldType.numeric),
  regCmd(13, 'Reg Cmd', FieldType.string),
  key(14, 'Key', FieldType.string),
  devId(15, 'Device ID', FieldType.string),
  devType(16, 'Device Type', FieldType.string),
  devProg(17, 'Device Prog', FieldType.string),
  exId(18, 'Ex ID', FieldType.string),
  position(19, 'Position', FieldType.string),
  errText(20, 'Error Text', FieldType.string),
  buttonId(21, 'Button ID', FieldType.string),
  idFamily(22, 'ID Family', FieldType.string),
  tare(23, 'Tare', FieldType.numeric),
  barcode(24, 'Barcode', FieldType.string),
  saddles(25, 'Saddles', FieldType.numeric),
  nominal(26, 'Nominal', FieldType.numeric),
  target(27, 'Target', FieldType.numeric),
  fGiveaway(28, 'Giveaway', FieldType.numeric),
  vGiveaway(29, 'V Giveaway', FieldType.numeric),
  tareType(30, 'Tare Type', FieldType.string),
  serialNumber(31, 'Serial Number', FieldType.string),
  stdDevA(32, 'Std Dev A', FieldType.numeric),
  resultCode(33, 'Result Code', FieldType.string),
  date(34, 'Date', FieldType.string),
  time(35, 'Time', FieldType.string),
  timeMs(36, 'Time Ms', FieldType.numeric),
  scaleRange(37, 'Scale Range', FieldType.string),
  weighingStatus(38, 'Weighing Status', FieldType.string),
  programId(39, 'Program ID', FieldType.string),
  programName(40, 'Program Name', FieldType.string),
  minWeight(41, 'Min Weight', FieldType.numeric),
  maxWeight(42, 'Max Weight', FieldType.numeric),
  alibi(43, 'Alibi', FieldType.string),
  division(44, 'Division', FieldType.string),
  recordId(45, 'Record ID', FieldType.string),
  rejectReason(46, 'Reject Reason', FieldType.string),
  originLabel(47, 'Origin Label', FieldType.string),
  tareDevice(48, 'Tare Device', FieldType.string),
  tareAlibi(49, 'Tare Alibi', FieldType.string),
  packId(50, 'Pack ID', FieldType.string),
  checksum(51, 'Checksum', FieldType.string),
  alibiText(52, 'Alibi Text', FieldType.string);

  final int id;
  final String displayName;
  final FieldType fieldType;

  const M2400Field(this.id, this.displayName, this.fieldType);

  static M2400Field? fromId(int id) {
    for (final f in values) {
      if (f.id == id) return f;
    }
    return null;
  }
}
