import 'dart:async';
import 'dart:ffi';

import 'package:tfc_core/core/collector.dart';
import 'package:tfc_core/core/database.dart';

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
  Logger.defaultFilter = () => TraceFilter();
  final logger = Logger();

  // final prefs = await Preferences.create(db: null);
  // final stateManConfig = await StateManConfig.fromPrefs(prefs);
  final smConfig = StateManConfig(
      opcua: [OpcUAConfig()..endpoint = "opc.tcp://10.50.10.10:4840"]);
  final key = "mytest";
  final keyMappings = KeyMappings(nodes: {});
  for (var i = 0; i < 100; i++) {
    final mykey = "$key$i";
    keyMappings.nodes.addAll({
      mykey: KeyMappingEntry(
          opcuaNode: OpcUANodeConfig(
        namespace: 4,
        identifier: "GVL_IO.TemperatureSensor.hmi.Mapped_values",
      )..arrayIndex = 2)
        ..collect = CollectEntry(key: mykey)
    });
  }
  final dbConfig = DatabaseConfig(
      postgres: Endpoint(
          host: "10.50.10.11",
          database: "hmi",
          username: "centroid",
          password: "FooBarHelloWorld"),
      sslMode: SslMode.require);
  final da = DataAcquisition(
      config: smConfig, mappings: keyMappings, dbConfig: dbConfig);

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
