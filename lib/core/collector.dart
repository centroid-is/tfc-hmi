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
  final Map<CollectEntry, StreamSubscription<DynamicValue>> _subscriptions = {};
  final Map<CollectEntry, Stream<DynamicValue>> _realTimeStreams = {};
  final Map<CollectEntry, AutoDisposingStream<List<TimeseriesData<dynamic>>>>
      _collectStreams = {};
  final Logger logger = Logger();

  static const configLocation = 'collector_config';

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

    subscription = subscription.asBroadcastStream();

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

    _subscriptions[entry] = subscription.listen(
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

    _realTimeStreams[entry] = subscription;
  }

  /// Returns a Stream of the collected data.
  /// This stream provides both historical data and real-time updates.
  Stream<List<TimeseriesData<dynamic>>> collectStream(String key,
      {Duration since = const Duration(days: 1)}) {
    // Find the CollectEntry for this key
    final entry = _subscriptions.keys.firstWhere((e) => e.key == key);
    final rtStream = _realTimeStreams[entry]!;
    final sinceTime = DateTime.now().toUtc().subtract(since);

    // Check if we already have a subscription entry for this key
    if (_collectStreams.containsKey(entry)) {
      return _collectStreams[entry]!.stream;
    }

    final subscriptionEntry =
        AutoDisposingStream<List<TimeseriesData<dynamic>>>(
      entry.name ?? entry.key,
      (name) {
        _collectStreams.remove(entry);
        logger.d('Removed collect stream entry for $name');
      },
      idleTimeout: const Duration(minutes: 30),
    );

    _collectStreams[entry] = subscriptionEntry;

    // Create a stream controller for real-time updates
    final streamController =
        StreamController<List<TimeseriesData<dynamic>>>.broadcast();

    StreamSubscription<DynamicValue>? realTimeSubscription;

    streamController.onListen = () async {
      try {
        List<TimeseriesData<dynamic>>? historicalData = [];
        final List<TimeseriesData<dynamic>> buffer = [];
        realTimeSubscription = rtStream.listen(
          (value) {
            final newSample = TimeseriesData<dynamic>(
              const DynamicValueConverter().toJson(value, slim: true),
              DateTime.now().toUtc(),
            );
            if (historicalData == null) {
              buffer.add(newSample);
              return;
            }
            historicalData.add(newSample);

            // Remove old data outside the retention window
            final cutoffTime = DateTime.now().toUtc().subtract(since);
            historicalData
                .removeWhere((sample) => sample.time.isBefore(cutoffTime));

            streamController.add(historicalData);
          },
          onError: (error, stackTrace) {
            logger.e('Error collecting data for key $key',
                error: error, stackTrace: stackTrace);
          },
        );
        historicalData = await database.queryTimeseriesData(
            entry.name ?? entry.key, sinceTime);
        historicalData.addAll(buffer);
        buffer.clear();

        streamController.add(historicalData);
      } catch (e) {
        logger.e('Failed to load historical data for key $key: $e');
        streamController.addError(e);
      }
    };

    // Use the raw stream to feed the subscription entry
    subscriptionEntry.subscribe(streamController.stream, null);

    // Clean up when the stream is cancelled
    streamController.onCancel = () {
      realTimeSubscription?.cancel();
      streamController.close();
    };

    return subscriptionEntry.stream;
  }

  /// Stop a collection.
  void stopCollect(CollectEntry entry) {
    _subscriptions[entry]?.cancel();
    _subscriptions.remove(entry);
  }
}
