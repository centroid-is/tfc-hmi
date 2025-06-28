import 'dart:async';

import 'package:logger/logger.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:open62541/open62541.dart' show DynamicValue;

import 'dynamic_value_converter.dart';
import 'state_man.dart';
import 'database.dart';
import 'duration_converter.dart';

part 'collector.g.dart';

@JsonSerializable()
class CollectEntry {
  String key;
  String? name;
  @DurationMinutesConverter()
  RetentionPolicy retention;
  @DurationMicrosecondsConverter()
  @JsonKey(name: 'sample_interval_us')
  Duration? sampleInterval; // microseconds

  CollectEntry(
      {required this.key,
      this.name,
      this.sampleInterval,
      this.retention = const RetentionPolicy(
          dropAfter: Duration(days: 365), scheduleInterval: null)}) {
    name ??= key;
  }
  Map<String, dynamic> toJson() => _$CollectEntryToJson(this);
  static CollectEntry fromJson(Map<String, dynamic> json) =>
      _$CollectEntryFromJson(json);
}

// TODO: implement this
// @JsonSerializable()
// class CollectTable {
//   String name;
//   List<CollectEntry> entries;

//   CollectTable({
//     required this.name,
//     required this.entries,
//   });
//   Map<String, dynamic> toJson() => _$CollectTableToJson(this);
//   static CollectTable fromJson(Map<String, dynamic> json) =>
//       _$CollectTableFromJson(json);
// }

@JsonSerializable()
class CollectorConfig {
  bool collect; // if false, no collection will be done
  // List<CollectTable> tables;

  CollectorConfig({this.collect = true});

  Map<String, dynamic> toJson() => _$CollectorConfigToJson(this);
  static CollectorConfig fromJson(Map<String, dynamic> json) =>
      _$CollectorConfigFromJson(json);
}

class Collector {
  final CollectorConfig config;
  final StateMan stateMan;
  final Database database;
  final Map<CollectEntry, StreamSubscription<DynamicValue>> subscriptions = {};
  final Logger logger = Logger();

  Collector({
    required this.config,
    required this.stateMan,
    required this.database,
  }) {
    final keyMappings = stateMan.keyMappings;
    for (var value in keyMappings.nodes.values) {
      if (value.collect != null) {
        collectEntry(value.collect!);
      }
    }
  }

  /// Initiate a collection of data from a node.
  /// Returns when the collection is started.
  Future<void> collectEntry(CollectEntry entry) async {
    final subscription = await stateMan.subscribe(entry.key);
    await collectEntryImpl(entry, subscription);
  }

  Future<void> collectEntryImpl(
      CollectEntry entry, Stream<DynamicValue> subscription) async {
    final name = entry.name ?? entry.key;
    await database.registerRetentionPolicy(name, entry.retention);

    // Variables for sampling logic
    Timer? sampleTimer;
    DynamicValue? latestValue;

    Future<void> insertValue(DynamicValue newValue) async {
      await database.insertTimeseriesData(
        name,
        DateTime.now().toUtc(),
        const DynamicValueConverter().toJson(newValue, slim: true),
      );
    }

    subscriptions[entry] = subscription.listen(
      (value) async {
        if (entry.sampleInterval == null) {
          // No sampling - collect every value immediately
          await insertValue(value);
        } else {
          // Store the latest value for periodic sampling
          latestValue = value;
        }
      },
      onError: (error, stackTrace) {
        logger.e('Error collecting data for key $name',
            error: error, stackTrace: stackTrace);
      },
      onDone: () {
        logger.i('Collection for key $name done');
        // Clean up timer when stream is done
        sampleTimer?.cancel();
      },
    );

    // Set up periodic sampling if sample interval is specified
    if (entry.sampleInterval != null) {
      sampleTimer = Timer.periodic(entry.sampleInterval!, (timer) async {
        if (latestValue != null) {
          final val = latestValue!;
          latestValue = null;
          await insertValue(val);
        }
      });
    }
  }

  /// Returns a Stream of the collected data.
  /// This stream provides both historical data and real-time updates.
  Stream<List<TimeseriesData<dynamic>>> collectStream(String key,
      {Duration since = const Duration(days: 1)}) async* {
    final entry = subscriptions.keys.firstWhere((e) => e.key == key);
    final stream = subscriptions[entry]!;
    final sinceTime = DateTime.now().toUtc().subtract(since);
    // final historicalData =
    //     await database.queryTimeseriesData(entry.name ?? entry.key, sinceTime);

    // // Convert historical data to CollectedSample objects
    // final historicalSamples = historicalData.map((row) {
    //   final value = row[1]; // JSONB value
    //   return CollectedSample(value, row[0] as DateTime);
    // }).toList();

    // // Create a stream controller for real-time updates
    // final streamController =
    //     StreamController<List<CollectedSample>>.broadcast();

    // // Start with historical data
    // streamController.add(historicalSamples);

    // // Subscribe to real-time updates if we have an active subscription
    // StreamSubscription<DynamicValue>? realTimeSubscription;
    // if (subscriptions.containsKey(key)) {
    //   // We already have a subscription, so we need to create a new one for this stream
    //   try {
    //     final realTimeStream = await stateMan.subscribe(key);
    //     realTimeSubscription = realTimeStream.listen(
    //       (value) {
    //         final newSample = CollectedSample(
    //           const DynamicValueConverter().toJson(value, slim: true),
    //           DateTime.now().toUtc(),
    //         );

    //         // Add new sample to the list and emit updated list
    //         final updatedSamples = List<CollectedSample>.from(historicalSamples)
    //           ..add(newSample);

    //         // Keep only samples within the retention period
    //         final cutoffTime = DateTime.now().toUtc().subtract(since);
    //         updatedSamples
    //             .removeWhere((sample) => sample.time.isBefore(cutoffTime));

    //         streamController.add(updatedSamples);
    //       },
    //       onError: (error, stackTrace) {
    //         logger.e('Error in real-time collection stream for key $key',
    //             error: error, stackTrace: stackTrace);
    //         streamController.addError(error, stackTrace);
    //       },
    //     );
    //   } catch (e) {
    //     logger.e('Failed to subscribe to real-time updates for key $key: $e');
    //     // Continue with historical data only
    //   }
    // }

    // // Yield the stream
    // yield* streamController.stream;

    // // Clean up when the stream is cancelled
    // streamController.onCancel = () {
    //   realTimeSubscription?.cancel();
    //   streamController.close();
    // };
  }

  /// Stop a collection.
  void stopCollect(CollectEntry entry) {
    subscriptions[entry]?.cancel();
    subscriptions.remove(entry);
  }
}
