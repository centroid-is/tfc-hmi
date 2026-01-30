import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

import 'package:tfc_dart/core/database.dart';
import 'package:tfc_dart/core/database_drift.dart';
import 'package:tfc_dart/core/preferences.dart';
import 'package:tfc_dart/core/state_man.dart';
import 'package:tfc_dart/core/alarm.dart';

import 'package:logger/logger.dart';
import 'data_acquisition_isolate.dart';

class TraceFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true; // Allow all log levels including trace
  }
}

void main() async {
  Logger.defaultFilter = () => TraceFilter();
  final logger = Logger();

  final dbConfig = await DatabaseConfig.fromEnv();
  final db = Database(await AppDatabase.spawn(dbConfig));
  final prefs = await Preferences.create(db: db);

  final statemanConfigFilePath =
      Platform.environment['CENTROID_STATEMAN_FILE_PATH'];
  if (statemanConfigFilePath == null) {
    throw Exception("Stateman Config file path needs to be set");
  }
  final smConfig = await StateManConfig.fromFile(statemanConfigFilePath);

  final keyMappings = await KeyMappings.fromPrefs(prefs, createDefault: false);

  // Generate a separate certificate for the alarm StateMan to avoid conflicts
  // when two clients connect with the same certificate
  final alarmSmConfig = smConfig.copy();
  for (final opcuaConfig in alarmSmConfig.opcua) {
    if (opcuaConfig.sslCert != null && opcuaConfig.sslKey != null) {
      final (cert, key) = _generateSelfSignedCert();
      opcuaConfig.sslCert = cert;
      opcuaConfig.sslKey = key;
    }
  }

  // Create StateMan for alarm monitoring (with separate certificate)
  final stateMan = await StateMan.create(
    config: alarmSmConfig,
    keyMappings: keyMappings,
    useIsolate: false,
  );

  // Setup alarm monitoring with database persistence
  // ignore: unused_local_variable
  final alarmHandler = await AlarmMan.create(
    prefs,
    stateMan,
    historyToDb: true,
  );

  logger.i('Spawning ${smConfig.opcua.length} DataAcquisition isolate(s)');

  // Spawn one isolate per OPC UA server
  for (final server in smConfig.opcua) {
    final filtered = keyMappings.filterByServer(server.serverAlias);
    final collectedKeys = filtered.nodes.entries
        .where((e) => e.value.collect != null)
        .map((e) => e.key);
    logger.i(
        'Spawning isolate for server ${server.serverAlias} ${server.endpoint} with ${filtered.nodes.length} keys (${collectedKeys.length} collected):\n${collectedKeys.map((k) => '  - $k').join('\n')}');

    await spawnDataAcquisitionIsolate(
      server: server,
      dbConfig: dbConfig,
      keyMappings: filtered,
    );
  }

  logger.i('All isolates spawned, main thread waiting...');

  // Keep main alive indefinitely
  await Completer<void>().future;
}

/// Generates a self-signed certificate and private key using basic_utils.
/// Returns a tuple of (certificate, privateKey) as Uint8List.
(Uint8List, Uint8List) _generateSelfSignedCert() {
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);

  final attributes = {
    'CN': 'AlarmHandler',
    'O': 'Centroid',
    'OU': 'OPC-UA',
    'C': 'IS',
    'ST': 'Hofudborgarsvaedid',
    'L': 'Hafnarfjordur',
  };

  final csr = X509Utils.generateRsaCsrPem(
    attributes,
    keyPair.privateKey as RSAPrivateKey,
    keyPair.publicKey as RSAPublicKey,
    san: ['localhost', '127.0.0.1'],
  );

  final certPem = X509Utils.generateSelfSignedCertificate(
    keyPair.privateKey as RSAPrivateKey,
    csr,
    3650,
    sans: ['localhost', '127.0.0.1'],
  );

  final keyPem = CryptoUtils.encodeRSAPrivateKeyToPem(
      keyPair.privateKey as RSAPrivateKey);

  final cert = Uint8List.fromList(utf8.encode(certPem));
  final key = Uint8List.fromList(utf8.encode(keyPem));

  return (cert, key);
}
