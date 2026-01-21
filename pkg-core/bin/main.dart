import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:args/args.dart';

import 'package:tfc_core/core/collector.dart';
import 'package:tfc_core/core/database.dart';
import 'package:tfc_core/core/database_drift.dart';
import 'package:tfc_core/core/preferences.dart';
import 'package:tfc_core/core/secure_storage/secure_storage.dart';

import 'data_acquisition.dart';
import 'package:tfc_core/core/state_man.dart';
import 'package:postgres/postgres.dart';

import 'package:open62541/open62541.dart';

import 'package:logger/logger.dart';

class TraceFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true; // Allow all log levels including trace
  }
}

void main() async {
  final databaseConfig = await DatabaseConfig.fromEnv();
  final db = Database(await AppDatabase.spawn(databaseConfig));
  final prefs =
      Preferences(database: db, secureStorage: SecureStorage.getInstance());

  final statemanConfigFilePath =
      Platform.environment['CENTROID_STATEMAN_FILE_PATH'];
  if (statemanConfigFilePath == null) {
    throw Exception("Stateman Config file path needs to be set");
  }
  final smConfig = await StateManConfig.fromFile(statemanConfigFilePath);

  Logger.defaultFilter = () => TraceFilter();

  final dbConfig = DatabaseConfig(
      postgres: Endpoint(
          host: "10.50.10.11",
          database: "hmi",
          username: "centroid",
          password: "FooBarHelloWorld"),
      sslMode: SslMode.require);

  // look at the config, we need to split each server from stateman, and create DataAcquisition for each server in an isolate
  final da = DataAcquisition(
      config: smConfig, dbConfig: dbConfig, enableStatsLogging: false);

  await Future.delayed(Duration(hours: 1));

  // final lib = loadOpen62541Library(staticLinking: false);
  // final client = Client(lib);

  // // spawn a background task to keep the client active
  // () async {
  //   final clientref = client;
  //   while (true) {
  //     final endpoint = "opc.tcp://10.50.10.10:4840";
  //     clientref.connect(endpoint).onError(
  //         (e, stacktrace) => logger.e('Failed to connect to ${endpoint}: $e'));
  //     while (clientref.runIterate(const Duration(milliseconds: 10)) && true) {
  //       await Future.delayed(const Duration(milliseconds: 10));
  //     }
  //     logger.e('Disconnecting client');
  //     clientref.disconnect();
  //     await Future.delayed(const Duration(milliseconds: 1000));
  //   }
  //   logger.e('StateMan background run iterate task exited');
  // }();

  // final foo = await client.awaitConnect();

  // await Future.delayed(Duration(seconds: 5));

  // final subid = await client.subscriptionCreate();

  // var cnts = <int>[];
  // for (var i = 0; i < 100; i++) {
  //   cnts.add(0);
  //   client
  //       .monitor(
  //           NodeId.fromString(4, "GVL_IO.TemperatureSensor.hmi.Mapped_values"),
  //           subid)
  //       .listen((val) {
  //     cnts[i] = cnts[i] + 1;
  //     if (i == 99) {
  //       print(cnts);
  //     }
  //   });
  // }
}
