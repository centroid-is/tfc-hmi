/// Web stub for package:jbtm/src/m2400.dart

enum M2400RecordType {
  recWgt(3),
  recIntro(5),
  recStat(14),
  recLua(87),
  recBatch(103),
  unknown(-1);

  final int id;
  const M2400RecordType(this.id);

  static M2400RecordType fromId(int id) {
    return M2400RecordType.values.firstWhere(
      (e) => e.id == id,
      orElse: () => M2400RecordType.unknown,
    );
  }
}
