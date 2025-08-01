// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_drift.dart';

// ignore_for_file: type=lint
class $AlarmTable extends Alarm with TableInfo<$AlarmTable, AlarmConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
      'uid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rulesMeta = const VerificationMeta('rules');
  @override
  late final GeneratedColumn<String> rules = GeneratedColumn<String>(
      'rules', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [uid, key, title, description, rules];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarm';
  @override
  VerificationContext validateIntegrity(Insertable<AlarmConfig> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('uid')) {
      context.handle(
          _uidMeta, uid.isAcceptableOrUnknown(data['uid']!, _uidMeta));
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('rules')) {
      context.handle(
          _rulesMeta, rules.isAcceptableOrUnknown(data['rules']!, _rulesMeta));
    } else if (isInserting) {
      context.missing(_rulesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {uid};
  @override
  AlarmConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmConfig.fromDb(
      uid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uid'])!,
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key']),
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      rules: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rules'])!,
    );
  }

  @override
  $AlarmTable createAlias(String alias) {
    return $AlarmTable(attachedDatabase, alias);
  }
}

class AlarmCompanion extends UpdateCompanion<AlarmConfig> {
  final Value<String> uid;
  final Value<String?> key;
  final Value<String> title;
  final Value<String> description;
  final Value<String> rules;
  final Value<int> rowid;
  const AlarmCompanion({
    this.uid = const Value.absent(),
    this.key = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.rules = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlarmCompanion.insert({
    required String uid,
    this.key = const Value.absent(),
    required String title,
    required String description,
    required String rules,
    this.rowid = const Value.absent(),
  })  : uid = Value(uid),
        title = Value(title),
        description = Value(description),
        rules = Value(rules);
  static Insertable<AlarmConfig> custom({
    Expression<String>? uid,
    Expression<String>? key,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? rules,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (uid != null) 'uid': uid,
      if (key != null) 'key': key,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (rules != null) 'rules': rules,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlarmCompanion copyWith(
      {Value<String>? uid,
      Value<String?>? key,
      Value<String>? title,
      Value<String>? description,
      Value<String>? rules,
      Value<int>? rowid}) {
    return AlarmCompanion(
      uid: uid ?? this.uid,
      key: key ?? this.key,
      title: title ?? this.title,
      description: description ?? this.description,
      rules: rules ?? this.rules,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (rules.present) {
      map['rules'] = Variable<String>(rules.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmCompanion(')
          ..write('uid: $uid, ')
          ..write('key: $key, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('rules: $rules, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlarmHistoryTable extends AlarmHistory
    with TableInfo<$AlarmHistoryTable, AlarmHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlarmHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _alarmUidMeta =
      const VerificationMeta('alarmUid');
  @override
  late final GeneratedColumn<String> alarmUid = GeneratedColumn<String>(
      'alarm_uid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES alarm (uid)'));
  static const VerificationMeta _alarmTitleMeta =
      const VerificationMeta('alarmTitle');
  @override
  late final GeneratedColumn<String> alarmTitle = GeneratedColumn<String>(
      'alarm_title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _alarmDescriptionMeta =
      const VerificationMeta('alarmDescription');
  @override
  late final GeneratedColumn<String> alarmDescription = GeneratedColumn<String>(
      'alarm_description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _alarmLevelMeta =
      const VerificationMeta('alarmLevel');
  @override
  late final GeneratedColumn<String> alarmLevel = GeneratedColumn<String>(
      'alarm_level', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _expressionMeta =
      const VerificationMeta('expression');
  @override
  late final GeneratedColumn<String> expression = GeneratedColumn<String>(
      'expression', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active =
      GeneratedColumn<bool>('active', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: true,
          defaultConstraints: GeneratedColumn.constraintsDependsOnDialect({
            SqlDialect.sqlite: 'CHECK ("active" IN (0, 1))',
            SqlDialect.postgres: '',
          }));
  static const VerificationMeta _pendingAckMeta =
      const VerificationMeta('pendingAck');
  @override
  late final GeneratedColumn<bool> pendingAck =
      GeneratedColumn<bool>('pending_ack', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: true,
          defaultConstraints: GeneratedColumn.constraintsDependsOnDialect({
            SqlDialect.sqlite: 'CHECK ("pending_ack" IN (0, 1))',
            SqlDialect.postgres: '',
          }));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _deactivatedAtMeta =
      const VerificationMeta('deactivatedAt');
  @override
  late final GeneratedColumn<DateTime> deactivatedAt =
      GeneratedColumn<DateTime>('deactivated_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _acknowledgedAtMeta =
      const VerificationMeta('acknowledgedAt');
  @override
  late final GeneratedColumn<DateTime> acknowledgedAt =
      GeneratedColumn<DateTime>('acknowledged_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        alarmUid,
        alarmTitle,
        alarmDescription,
        alarmLevel,
        expression,
        active,
        pendingAck,
        createdAt,
        deactivatedAt,
        acknowledgedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'alarm_history';
  @override
  VerificationContext validateIntegrity(Insertable<AlarmHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('alarm_uid')) {
      context.handle(_alarmUidMeta,
          alarmUid.isAcceptableOrUnknown(data['alarm_uid']!, _alarmUidMeta));
    } else if (isInserting) {
      context.missing(_alarmUidMeta);
    }
    if (data.containsKey('alarm_title')) {
      context.handle(
          _alarmTitleMeta,
          alarmTitle.isAcceptableOrUnknown(
              data['alarm_title']!, _alarmTitleMeta));
    } else if (isInserting) {
      context.missing(_alarmTitleMeta);
    }
    if (data.containsKey('alarm_description')) {
      context.handle(
          _alarmDescriptionMeta,
          alarmDescription.isAcceptableOrUnknown(
              data['alarm_description']!, _alarmDescriptionMeta));
    } else if (isInserting) {
      context.missing(_alarmDescriptionMeta);
    }
    if (data.containsKey('alarm_level')) {
      context.handle(
          _alarmLevelMeta,
          alarmLevel.isAcceptableOrUnknown(
              data['alarm_level']!, _alarmLevelMeta));
    } else if (isInserting) {
      context.missing(_alarmLevelMeta);
    }
    if (data.containsKey('expression')) {
      context.handle(
          _expressionMeta,
          expression.isAcceptableOrUnknown(
              data['expression']!, _expressionMeta));
    }
    if (data.containsKey('active')) {
      context.handle(_activeMeta,
          active.isAcceptableOrUnknown(data['active']!, _activeMeta));
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    if (data.containsKey('pending_ack')) {
      context.handle(
          _pendingAckMeta,
          pendingAck.isAcceptableOrUnknown(
              data['pending_ack']!, _pendingAckMeta));
    } else if (isInserting) {
      context.missing(_pendingAckMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('deactivated_at')) {
      context.handle(
          _deactivatedAtMeta,
          deactivatedAt.isAcceptableOrUnknown(
              data['deactivated_at']!, _deactivatedAtMeta));
    }
    if (data.containsKey('acknowledged_at')) {
      context.handle(
          _acknowledgedAtMeta,
          acknowledgedAt.isAcceptableOrUnknown(
              data['acknowledged_at']!, _acknowledgedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlarmHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlarmHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      alarmUid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}alarm_uid'])!,
      alarmTitle: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}alarm_title'])!,
      alarmDescription: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}alarm_description'])!,
      alarmLevel: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}alarm_level'])!,
      expression: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}expression']),
      active: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}active'])!,
      pendingAck: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}pending_ack'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      deactivatedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}deactivated_at']),
      acknowledgedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}acknowledged_at']),
    );
  }

  @override
  $AlarmHistoryTable createAlias(String alias) {
    return $AlarmHistoryTable(attachedDatabase, alias);
  }
}

class AlarmHistoryData extends DataClass
    implements Insertable<AlarmHistoryData> {
  final int id;
  final String alarmUid;
  final String alarmTitle;
  final String alarmDescription;
  final String alarmLevel;
  final String? expression;
  final bool active;
  final bool pendingAck;
  final DateTime createdAt;
  final DateTime? deactivatedAt;
  final DateTime? acknowledgedAt;
  const AlarmHistoryData(
      {required this.id,
      required this.alarmUid,
      required this.alarmTitle,
      required this.alarmDescription,
      required this.alarmLevel,
      this.expression,
      required this.active,
      required this.pendingAck,
      required this.createdAt,
      this.deactivatedAt,
      this.acknowledgedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['alarm_uid'] = Variable<String>(alarmUid);
    map['alarm_title'] = Variable<String>(alarmTitle);
    map['alarm_description'] = Variable<String>(alarmDescription);
    map['alarm_level'] = Variable<String>(alarmLevel);
    if (!nullToAbsent || expression != null) {
      map['expression'] = Variable<String>(expression);
    }
    map['active'] = Variable<bool>(active);
    map['pending_ack'] = Variable<bool>(pendingAck);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || deactivatedAt != null) {
      map['deactivated_at'] = Variable<DateTime>(deactivatedAt);
    }
    if (!nullToAbsent || acknowledgedAt != null) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt);
    }
    return map;
  }

  AlarmHistoryCompanion toCompanion(bool nullToAbsent) {
    return AlarmHistoryCompanion(
      id: Value(id),
      alarmUid: Value(alarmUid),
      alarmTitle: Value(alarmTitle),
      alarmDescription: Value(alarmDescription),
      alarmLevel: Value(alarmLevel),
      expression: expression == null && nullToAbsent
          ? const Value.absent()
          : Value(expression),
      active: Value(active),
      pendingAck: Value(pendingAck),
      createdAt: Value(createdAt),
      deactivatedAt: deactivatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deactivatedAt),
      acknowledgedAt: acknowledgedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAt),
    );
  }

  factory AlarmHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlarmHistoryData(
      id: serializer.fromJson<int>(json['id']),
      alarmUid: serializer.fromJson<String>(json['alarmUid']),
      alarmTitle: serializer.fromJson<String>(json['alarmTitle']),
      alarmDescription: serializer.fromJson<String>(json['alarmDescription']),
      alarmLevel: serializer.fromJson<String>(json['alarmLevel']),
      expression: serializer.fromJson<String?>(json['expression']),
      active: serializer.fromJson<bool>(json['active']),
      pendingAck: serializer.fromJson<bool>(json['pendingAck']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      deactivatedAt: serializer.fromJson<DateTime?>(json['deactivatedAt']),
      acknowledgedAt: serializer.fromJson<DateTime?>(json['acknowledgedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'alarmUid': serializer.toJson<String>(alarmUid),
      'alarmTitle': serializer.toJson<String>(alarmTitle),
      'alarmDescription': serializer.toJson<String>(alarmDescription),
      'alarmLevel': serializer.toJson<String>(alarmLevel),
      'expression': serializer.toJson<String?>(expression),
      'active': serializer.toJson<bool>(active),
      'pendingAck': serializer.toJson<bool>(pendingAck),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'deactivatedAt': serializer.toJson<DateTime?>(deactivatedAt),
      'acknowledgedAt': serializer.toJson<DateTime?>(acknowledgedAt),
    };
  }

  AlarmHistoryData copyWith(
          {int? id,
          String? alarmUid,
          String? alarmTitle,
          String? alarmDescription,
          String? alarmLevel,
          Value<String?> expression = const Value.absent(),
          bool? active,
          bool? pendingAck,
          DateTime? createdAt,
          Value<DateTime?> deactivatedAt = const Value.absent(),
          Value<DateTime?> acknowledgedAt = const Value.absent()}) =>
      AlarmHistoryData(
        id: id ?? this.id,
        alarmUid: alarmUid ?? this.alarmUid,
        alarmTitle: alarmTitle ?? this.alarmTitle,
        alarmDescription: alarmDescription ?? this.alarmDescription,
        alarmLevel: alarmLevel ?? this.alarmLevel,
        expression: expression.present ? expression.value : this.expression,
        active: active ?? this.active,
        pendingAck: pendingAck ?? this.pendingAck,
        createdAt: createdAt ?? this.createdAt,
        deactivatedAt:
            deactivatedAt.present ? deactivatedAt.value : this.deactivatedAt,
        acknowledgedAt:
            acknowledgedAt.present ? acknowledgedAt.value : this.acknowledgedAt,
      );
  AlarmHistoryData copyWithCompanion(AlarmHistoryCompanion data) {
    return AlarmHistoryData(
      id: data.id.present ? data.id.value : this.id,
      alarmUid: data.alarmUid.present ? data.alarmUid.value : this.alarmUid,
      alarmTitle:
          data.alarmTitle.present ? data.alarmTitle.value : this.alarmTitle,
      alarmDescription: data.alarmDescription.present
          ? data.alarmDescription.value
          : this.alarmDescription,
      alarmLevel:
          data.alarmLevel.present ? data.alarmLevel.value : this.alarmLevel,
      expression:
          data.expression.present ? data.expression.value : this.expression,
      active: data.active.present ? data.active.value : this.active,
      pendingAck:
          data.pendingAck.present ? data.pendingAck.value : this.pendingAck,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      deactivatedAt: data.deactivatedAt.present
          ? data.deactivatedAt.value
          : this.deactivatedAt,
      acknowledgedAt: data.acknowledgedAt.present
          ? data.acknowledgedAt.value
          : this.acknowledgedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlarmHistoryData(')
          ..write('id: $id, ')
          ..write('alarmUid: $alarmUid, ')
          ..write('alarmTitle: $alarmTitle, ')
          ..write('alarmDescription: $alarmDescription, ')
          ..write('alarmLevel: $alarmLevel, ')
          ..write('expression: $expression, ')
          ..write('active: $active, ')
          ..write('pendingAck: $pendingAck, ')
          ..write('createdAt: $createdAt, ')
          ..write('deactivatedAt: $deactivatedAt, ')
          ..write('acknowledgedAt: $acknowledgedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      alarmUid,
      alarmTitle,
      alarmDescription,
      alarmLevel,
      expression,
      active,
      pendingAck,
      createdAt,
      deactivatedAt,
      acknowledgedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlarmHistoryData &&
          other.id == this.id &&
          other.alarmUid == this.alarmUid &&
          other.alarmTitle == this.alarmTitle &&
          other.alarmDescription == this.alarmDescription &&
          other.alarmLevel == this.alarmLevel &&
          other.expression == this.expression &&
          other.active == this.active &&
          other.pendingAck == this.pendingAck &&
          other.createdAt == this.createdAt &&
          other.deactivatedAt == this.deactivatedAt &&
          other.acknowledgedAt == this.acknowledgedAt);
}

class AlarmHistoryCompanion extends UpdateCompanion<AlarmHistoryData> {
  final Value<int> id;
  final Value<String> alarmUid;
  final Value<String> alarmTitle;
  final Value<String> alarmDescription;
  final Value<String> alarmLevel;
  final Value<String?> expression;
  final Value<bool> active;
  final Value<bool> pendingAck;
  final Value<DateTime> createdAt;
  final Value<DateTime?> deactivatedAt;
  final Value<DateTime?> acknowledgedAt;
  const AlarmHistoryCompanion({
    this.id = const Value.absent(),
    this.alarmUid = const Value.absent(),
    this.alarmTitle = const Value.absent(),
    this.alarmDescription = const Value.absent(),
    this.alarmLevel = const Value.absent(),
    this.expression = const Value.absent(),
    this.active = const Value.absent(),
    this.pendingAck = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.deactivatedAt = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
  });
  AlarmHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String alarmUid,
    required String alarmTitle,
    required String alarmDescription,
    required String alarmLevel,
    this.expression = const Value.absent(),
    required bool active,
    required bool pendingAck,
    required DateTime createdAt,
    this.deactivatedAt = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
  })  : alarmUid = Value(alarmUid),
        alarmTitle = Value(alarmTitle),
        alarmDescription = Value(alarmDescription),
        alarmLevel = Value(alarmLevel),
        active = Value(active),
        pendingAck = Value(pendingAck),
        createdAt = Value(createdAt);
  static Insertable<AlarmHistoryData> custom({
    Expression<int>? id,
    Expression<String>? alarmUid,
    Expression<String>? alarmTitle,
    Expression<String>? alarmDescription,
    Expression<String>? alarmLevel,
    Expression<String>? expression,
    Expression<bool>? active,
    Expression<bool>? pendingAck,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? deactivatedAt,
    Expression<DateTime>? acknowledgedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (alarmUid != null) 'alarm_uid': alarmUid,
      if (alarmTitle != null) 'alarm_title': alarmTitle,
      if (alarmDescription != null) 'alarm_description': alarmDescription,
      if (alarmLevel != null) 'alarm_level': alarmLevel,
      if (expression != null) 'expression': expression,
      if (active != null) 'active': active,
      if (pendingAck != null) 'pending_ack': pendingAck,
      if (createdAt != null) 'created_at': createdAt,
      if (deactivatedAt != null) 'deactivated_at': deactivatedAt,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
    });
  }

  AlarmHistoryCompanion copyWith(
      {Value<int>? id,
      Value<String>? alarmUid,
      Value<String>? alarmTitle,
      Value<String>? alarmDescription,
      Value<String>? alarmLevel,
      Value<String?>? expression,
      Value<bool>? active,
      Value<bool>? pendingAck,
      Value<DateTime>? createdAt,
      Value<DateTime?>? deactivatedAt,
      Value<DateTime?>? acknowledgedAt}) {
    return AlarmHistoryCompanion(
      id: id ?? this.id,
      alarmUid: alarmUid ?? this.alarmUid,
      alarmTitle: alarmTitle ?? this.alarmTitle,
      alarmDescription: alarmDescription ?? this.alarmDescription,
      alarmLevel: alarmLevel ?? this.alarmLevel,
      expression: expression ?? this.expression,
      active: active ?? this.active,
      pendingAck: pendingAck ?? this.pendingAck,
      createdAt: createdAt ?? this.createdAt,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (alarmUid.present) {
      map['alarm_uid'] = Variable<String>(alarmUid.value);
    }
    if (alarmTitle.present) {
      map['alarm_title'] = Variable<String>(alarmTitle.value);
    }
    if (alarmDescription.present) {
      map['alarm_description'] = Variable<String>(alarmDescription.value);
    }
    if (alarmLevel.present) {
      map['alarm_level'] = Variable<String>(alarmLevel.value);
    }
    if (expression.present) {
      map['expression'] = Variable<String>(expression.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (pendingAck.present) {
      map['pending_ack'] = Variable<bool>(pendingAck.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (deactivatedAt.present) {
      map['deactivated_at'] = Variable<DateTime>(deactivatedAt.value);
    }
    if (acknowledgedAt.present) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlarmHistoryCompanion(')
          ..write('id: $id, ')
          ..write('alarmUid: $alarmUid, ')
          ..write('alarmTitle: $alarmTitle, ')
          ..write('alarmDescription: $alarmDescription, ')
          ..write('alarmLevel: $alarmLevel, ')
          ..write('expression: $expression, ')
          ..write('active: $active, ')
          ..write('pendingAck: $pendingAck, ')
          ..write('createdAt: $createdAt, ')
          ..write('deactivatedAt: $deactivatedAt, ')
          ..write('acknowledgedAt: $acknowledgedAt')
          ..write(')'))
        .toString();
  }
}

class $FlutterPreferencesTable extends FlutterPreferences
    with TableInfo<$FlutterPreferencesTable, FlutterPreference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FlutterPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value, type];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'flutter_preferences';
  @override
  VerificationContext validateIntegrity(Insertable<FlutterPreference> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  FlutterPreference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FlutterPreference(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value']),
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
    );
  }

  @override
  $FlutterPreferencesTable createAlias(String alias) {
    return $FlutterPreferencesTable(attachedDatabase, alias);
  }
}

class FlutterPreference extends DataClass
    implements Insertable<FlutterPreference> {
  final String key;
  final String? value;
  final String type;
  const FlutterPreference({required this.key, this.value, required this.type});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    map['type'] = Variable<String>(type);
    return map;
  }

  FlutterPreferencesCompanion toCompanion(bool nullToAbsent) {
    return FlutterPreferencesCompanion(
      key: Value(key),
      value:
          value == null && nullToAbsent ? const Value.absent() : Value(value),
      type: Value(type),
    );
  }

  factory FlutterPreference.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FlutterPreference(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String?>(json['value']),
      type: serializer.fromJson<String>(json['type']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String?>(value),
      'type': serializer.toJson<String>(type),
    };
  }

  FlutterPreference copyWith(
          {String? key,
          Value<String?> value = const Value.absent(),
          String? type}) =>
      FlutterPreference(
        key: key ?? this.key,
        value: value.present ? value.value : this.value,
        type: type ?? this.type,
      );
  FlutterPreference copyWithCompanion(FlutterPreferencesCompanion data) {
    return FlutterPreference(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      type: data.type.present ? data.type.value : this.type,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FlutterPreference(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('type: $type')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, type);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FlutterPreference &&
          other.key == this.key &&
          other.value == this.value &&
          other.type == this.type);
}

class FlutterPreferencesCompanion extends UpdateCompanion<FlutterPreference> {
  final Value<String> key;
  final Value<String?> value;
  final Value<String> type;
  final Value<int> rowid;
  const FlutterPreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.type = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FlutterPreferencesCompanion.insert({
    required String key,
    this.value = const Value.absent(),
    required String type,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        type = Value(type);
  static Insertable<FlutterPreference> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<String>? type,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (type != null) 'type': type,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FlutterPreferencesCompanion copyWith(
      {Value<String>? key,
      Value<String?>? value,
      Value<String>? type,
      Value<int>? rowid}) {
    return FlutterPreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      type: type ?? this.type,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FlutterPreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('type: $type, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AlarmTable alarm = $AlarmTable(this);
  late final $AlarmHistoryTable alarmHistory = $AlarmHistoryTable(this);
  late final $FlutterPreferencesTable flutterPreferences =
      $FlutterPreferencesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [alarm, alarmHistory, flutterPreferences];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$AlarmTableCreateCompanionBuilder = AlarmCompanion Function({
  required String uid,
  Value<String?> key,
  required String title,
  required String description,
  required String rules,
  Value<int> rowid,
});
typedef $$AlarmTableUpdateCompanionBuilder = AlarmCompanion Function({
  Value<String> uid,
  Value<String?> key,
  Value<String> title,
  Value<String> description,
  Value<String> rules,
  Value<int> rowid,
});

final class $$AlarmTableReferences
    extends BaseReferences<_$AppDatabase, $AlarmTable, AlarmConfig> {
  $$AlarmTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AlarmHistoryTable, List<AlarmHistoryData>>
      _alarmHistoryRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.alarmHistory,
              aliasName:
                  $_aliasNameGenerator(db.alarm.uid, db.alarmHistory.alarmUid));

  $$AlarmHistoryTableProcessedTableManager get alarmHistoryRefs {
    final manager = $$AlarmHistoryTableTableManager($_db, $_db.alarmHistory)
        .filter((f) => f.alarmUid.uid.sqlEquals($_itemColumn<String>('uid')!));

    final cache = $_typedResult.readTableOrNull(_alarmHistoryRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$AlarmTableFilterComposer extends Composer<_$AppDatabase, $AlarmTable> {
  $$AlarmTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get uid => $composableBuilder(
      column: $table.uid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rules => $composableBuilder(
      column: $table.rules, builder: (column) => ColumnFilters(column));

  Expression<bool> alarmHistoryRefs(
      Expression<bool> Function($$AlarmHistoryTableFilterComposer f) f) {
    final $$AlarmHistoryTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.uid,
        referencedTable: $db.alarmHistory,
        getReferencedColumn: (t) => t.alarmUid,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlarmHistoryTableFilterComposer(
              $db: $db,
              $table: $db.alarmHistory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$AlarmTableOrderingComposer
    extends Composer<_$AppDatabase, $AlarmTable> {
  $$AlarmTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get uid => $composableBuilder(
      column: $table.uid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rules => $composableBuilder(
      column: $table.rules, builder: (column) => ColumnOrderings(column));
}

class $$AlarmTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlarmTable> {
  $$AlarmTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get rules =>
      $composableBuilder(column: $table.rules, builder: (column) => column);

  Expression<T> alarmHistoryRefs<T extends Object>(
      Expression<T> Function($$AlarmHistoryTableAnnotationComposer a) f) {
    final $$AlarmHistoryTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.uid,
        referencedTable: $db.alarmHistory,
        getReferencedColumn: (t) => t.alarmUid,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlarmHistoryTableAnnotationComposer(
              $db: $db,
              $table: $db.alarmHistory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$AlarmTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AlarmTable,
    AlarmConfig,
    $$AlarmTableFilterComposer,
    $$AlarmTableOrderingComposer,
    $$AlarmTableAnnotationComposer,
    $$AlarmTableCreateCompanionBuilder,
    $$AlarmTableUpdateCompanionBuilder,
    (AlarmConfig, $$AlarmTableReferences),
    AlarmConfig,
    PrefetchHooks Function({bool alarmHistoryRefs})> {
  $$AlarmTableTableManager(_$AppDatabase db, $AlarmTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlarmTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> uid = const Value.absent(),
            Value<String?> key = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> rules = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AlarmCompanion(
            uid: uid,
            key: key,
            title: title,
            description: description,
            rules: rules,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String uid,
            Value<String?> key = const Value.absent(),
            required String title,
            required String description,
            required String rules,
            Value<int> rowid = const Value.absent(),
          }) =>
              AlarmCompanion.insert(
            uid: uid,
            key: key,
            title: title,
            description: description,
            rules: rules,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$AlarmTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({alarmHistoryRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (alarmHistoryRefs) db.alarmHistory],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (alarmHistoryRefs)
                    await $_getPrefetchedData<AlarmConfig, $AlarmTable,
                            AlarmHistoryData>(
                        currentTable: table,
                        referencedTable:
                            $$AlarmTableReferences._alarmHistoryRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$AlarmTableReferences(db, table, p0)
                                .alarmHistoryRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.alarmUid == item.uid),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$AlarmTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AlarmTable,
    AlarmConfig,
    $$AlarmTableFilterComposer,
    $$AlarmTableOrderingComposer,
    $$AlarmTableAnnotationComposer,
    $$AlarmTableCreateCompanionBuilder,
    $$AlarmTableUpdateCompanionBuilder,
    (AlarmConfig, $$AlarmTableReferences),
    AlarmConfig,
    PrefetchHooks Function({bool alarmHistoryRefs})>;
typedef $$AlarmHistoryTableCreateCompanionBuilder = AlarmHistoryCompanion
    Function({
  Value<int> id,
  required String alarmUid,
  required String alarmTitle,
  required String alarmDescription,
  required String alarmLevel,
  Value<String?> expression,
  required bool active,
  required bool pendingAck,
  required DateTime createdAt,
  Value<DateTime?> deactivatedAt,
  Value<DateTime?> acknowledgedAt,
});
typedef $$AlarmHistoryTableUpdateCompanionBuilder = AlarmHistoryCompanion
    Function({
  Value<int> id,
  Value<String> alarmUid,
  Value<String> alarmTitle,
  Value<String> alarmDescription,
  Value<String> alarmLevel,
  Value<String?> expression,
  Value<bool> active,
  Value<bool> pendingAck,
  Value<DateTime> createdAt,
  Value<DateTime?> deactivatedAt,
  Value<DateTime?> acknowledgedAt,
});

final class $$AlarmHistoryTableReferences extends BaseReferences<_$AppDatabase,
    $AlarmHistoryTable, AlarmHistoryData> {
  $$AlarmHistoryTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AlarmTable _alarmUidTable(_$AppDatabase db) => db.alarm.createAlias(
      $_aliasNameGenerator(db.alarmHistory.alarmUid, db.alarm.uid));

  $$AlarmTableProcessedTableManager get alarmUid {
    final $_column = $_itemColumn<String>('alarm_uid')!;

    final manager = $$AlarmTableTableManager($_db, $_db.alarm)
        .filter((f) => f.uid.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_alarmUidTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$AlarmHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $AlarmHistoryTable> {
  $$AlarmHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get alarmTitle => $composableBuilder(
      column: $table.alarmTitle, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get alarmDescription => $composableBuilder(
      column: $table.alarmDescription,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get alarmLevel => $composableBuilder(
      column: $table.alarmLevel, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get expression => $composableBuilder(
      column: $table.expression, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get active => $composableBuilder(
      column: $table.active, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get pendingAck => $composableBuilder(
      column: $table.pendingAck, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deactivatedAt => $composableBuilder(
      column: $table.deactivatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt,
      builder: (column) => ColumnFilters(column));

  $$AlarmTableFilterComposer get alarmUid {
    final $$AlarmTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.alarmUid,
        referencedTable: $db.alarm,
        getReferencedColumn: (t) => t.uid,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlarmTableFilterComposer(
              $db: $db,
              $table: $db.alarm,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AlarmHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $AlarmHistoryTable> {
  $$AlarmHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get alarmTitle => $composableBuilder(
      column: $table.alarmTitle, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get alarmDescription => $composableBuilder(
      column: $table.alarmDescription,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get alarmLevel => $composableBuilder(
      column: $table.alarmLevel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get expression => $composableBuilder(
      column: $table.expression, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get active => $composableBuilder(
      column: $table.active, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get pendingAck => $composableBuilder(
      column: $table.pendingAck, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deactivatedAt => $composableBuilder(
      column: $table.deactivatedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt,
      builder: (column) => ColumnOrderings(column));

  $$AlarmTableOrderingComposer get alarmUid {
    final $$AlarmTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.alarmUid,
        referencedTable: $db.alarm,
        getReferencedColumn: (t) => t.uid,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlarmTableOrderingComposer(
              $db: $db,
              $table: $db.alarm,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AlarmHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlarmHistoryTable> {
  $$AlarmHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get alarmTitle => $composableBuilder(
      column: $table.alarmTitle, builder: (column) => column);

  GeneratedColumn<String> get alarmDescription => $composableBuilder(
      column: $table.alarmDescription, builder: (column) => column);

  GeneratedColumn<String> get alarmLevel => $composableBuilder(
      column: $table.alarmLevel, builder: (column) => column);

  GeneratedColumn<String> get expression => $composableBuilder(
      column: $table.expression, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<bool> get pendingAck => $composableBuilder(
      column: $table.pendingAck, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deactivatedAt => $composableBuilder(
      column: $table.deactivatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt, builder: (column) => column);

  $$AlarmTableAnnotationComposer get alarmUid {
    final $$AlarmTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.alarmUid,
        referencedTable: $db.alarm,
        getReferencedColumn: (t) => t.uid,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlarmTableAnnotationComposer(
              $db: $db,
              $table: $db.alarm,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AlarmHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AlarmHistoryTable,
    AlarmHistoryData,
    $$AlarmHistoryTableFilterComposer,
    $$AlarmHistoryTableOrderingComposer,
    $$AlarmHistoryTableAnnotationComposer,
    $$AlarmHistoryTableCreateCompanionBuilder,
    $$AlarmHistoryTableUpdateCompanionBuilder,
    (AlarmHistoryData, $$AlarmHistoryTableReferences),
    AlarmHistoryData,
    PrefetchHooks Function({bool alarmUid})> {
  $$AlarmHistoryTableTableManager(_$AppDatabase db, $AlarmHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlarmHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlarmHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlarmHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> alarmUid = const Value.absent(),
            Value<String> alarmTitle = const Value.absent(),
            Value<String> alarmDescription = const Value.absent(),
            Value<String> alarmLevel = const Value.absent(),
            Value<String?> expression = const Value.absent(),
            Value<bool> active = const Value.absent(),
            Value<bool> pendingAck = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> deactivatedAt = const Value.absent(),
            Value<DateTime?> acknowledgedAt = const Value.absent(),
          }) =>
              AlarmHistoryCompanion(
            id: id,
            alarmUid: alarmUid,
            alarmTitle: alarmTitle,
            alarmDescription: alarmDescription,
            alarmLevel: alarmLevel,
            expression: expression,
            active: active,
            pendingAck: pendingAck,
            createdAt: createdAt,
            deactivatedAt: deactivatedAt,
            acknowledgedAt: acknowledgedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String alarmUid,
            required String alarmTitle,
            required String alarmDescription,
            required String alarmLevel,
            Value<String?> expression = const Value.absent(),
            required bool active,
            required bool pendingAck,
            required DateTime createdAt,
            Value<DateTime?> deactivatedAt = const Value.absent(),
            Value<DateTime?> acknowledgedAt = const Value.absent(),
          }) =>
              AlarmHistoryCompanion.insert(
            id: id,
            alarmUid: alarmUid,
            alarmTitle: alarmTitle,
            alarmDescription: alarmDescription,
            alarmLevel: alarmLevel,
            expression: expression,
            active: active,
            pendingAck: pendingAck,
            createdAt: createdAt,
            deactivatedAt: deactivatedAt,
            acknowledgedAt: acknowledgedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$AlarmHistoryTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({alarmUid = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (alarmUid) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.alarmUid,
                    referencedTable:
                        $$AlarmHistoryTableReferences._alarmUidTable(db),
                    referencedColumn:
                        $$AlarmHistoryTableReferences._alarmUidTable(db).uid,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$AlarmHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AlarmHistoryTable,
    AlarmHistoryData,
    $$AlarmHistoryTableFilterComposer,
    $$AlarmHistoryTableOrderingComposer,
    $$AlarmHistoryTableAnnotationComposer,
    $$AlarmHistoryTableCreateCompanionBuilder,
    $$AlarmHistoryTableUpdateCompanionBuilder,
    (AlarmHistoryData, $$AlarmHistoryTableReferences),
    AlarmHistoryData,
    PrefetchHooks Function({bool alarmUid})>;
typedef $$FlutterPreferencesTableCreateCompanionBuilder
    = FlutterPreferencesCompanion Function({
  required String key,
  Value<String?> value,
  required String type,
  Value<int> rowid,
});
typedef $$FlutterPreferencesTableUpdateCompanionBuilder
    = FlutterPreferencesCompanion Function({
  Value<String> key,
  Value<String?> value,
  Value<String> type,
  Value<int> rowid,
});

class $$FlutterPreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $FlutterPreferencesTable> {
  $$FlutterPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));
}

class $$FlutterPreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $FlutterPreferencesTable> {
  $$FlutterPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));
}

class $$FlutterPreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FlutterPreferencesTable> {
  $$FlutterPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);
}

class $$FlutterPreferencesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FlutterPreferencesTable,
    FlutterPreference,
    $$FlutterPreferencesTableFilterComposer,
    $$FlutterPreferencesTableOrderingComposer,
    $$FlutterPreferencesTableAnnotationComposer,
    $$FlutterPreferencesTableCreateCompanionBuilder,
    $$FlutterPreferencesTableUpdateCompanionBuilder,
    (
      FlutterPreference,
      BaseReferences<_$AppDatabase, $FlutterPreferencesTable, FlutterPreference>
    ),
    FlutterPreference,
    PrefetchHooks Function()> {
  $$FlutterPreferencesTableTableManager(
      _$AppDatabase db, $FlutterPreferencesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FlutterPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FlutterPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FlutterPreferencesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String?> value = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FlutterPreferencesCompanion(
            key: key,
            value: value,
            type: type,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            Value<String?> value = const Value.absent(),
            required String type,
            Value<int> rowid = const Value.absent(),
          }) =>
              FlutterPreferencesCompanion.insert(
            key: key,
            value: value,
            type: type,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FlutterPreferencesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $FlutterPreferencesTable,
    FlutterPreference,
    $$FlutterPreferencesTableFilterComposer,
    $$FlutterPreferencesTableOrderingComposer,
    $$FlutterPreferencesTableAnnotationComposer,
    $$FlutterPreferencesTableCreateCompanionBuilder,
    $$FlutterPreferencesTableUpdateCompanionBuilder,
    (
      FlutterPreference,
      BaseReferences<_$AppDatabase, $FlutterPreferencesTable, FlutterPreference>
    ),
    FlutterPreference,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AlarmTableTableManager get alarm =>
      $$AlarmTableTableManager(_db, _db.alarm);
  $$AlarmHistoryTableTableManager get alarmHistory =>
      $$AlarmHistoryTableTableManager(_db, _db.alarmHistory);
  $$FlutterPreferencesTableTableManager get flutterPreferences =>
      $$FlutterPreferencesTableTableManager(_db, _db.flutterPreferences);
}
