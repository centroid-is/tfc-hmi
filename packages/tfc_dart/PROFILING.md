# Profiling and Debugging High Resource Usage

This guide helps you profile and debug resource consumption issues in the data acquisition system.

## Quick Start

### 1. Launch with Profiling

Use the "Dart data acq (profile)" launch configuration in VSCode, which enables:
- `--profile` flag for production-like performance
- `--observe` flag to enable VM service for DevTools

### 2. Connect Dart DevTools

After launching with profile mode:

```bash
# From pkg-core directory
dart devtools
```

Then connect to the Observatory URL shown in the debug console.

### 3. Use Resource Monitor

Add resource monitoring to your code:

```dart
import 'resource_monitor.dart';

void main() async {
  final logger = Logger();
  final monitor = ResourceMonitor(logger);

  // Start monitoring every 5 seconds
  monitor.start(interval: Duration(seconds: 5));

  // Your application code...

  // Stop monitoring when done
  monitor.stop();
}
```

## Common Resource Issues

Based on the codebase analysis, here are likely causes of high resource usage:

### 1. **Excessive OPC UA Subscriptions**

**Issue:** Each subscribed key creates a monitored item on the OPC UA server.

**Location:** [state_man.dart:552-633](lib/core/state_man.dart#L552-L633)

**Debug:**
- Check subscription count: Monitor `_subscriptions.length` in StateMan
- Log when subscriptions are created/destroyed
- Verify AutoDisposingStream cleanup (10-minute idle timeout)

**Fix Options:**
- Reduce monitored keys
- Adjust `idleTimeout` in AutoDisposingStream
- Use `readMany()` instead of individual subscriptions for static reads

### 2. **Database Write Load**

**Issue:** Frequent database writes, especially with 100 keys.

**Location:** [collector.dart:144-150](lib/core/collector.dart#L144-L150)

**Debug:**
- Count inserts per second
- Monitor database connection pool
- Check if `sampleInterval` is too aggressive

**Fix Options:**
- Increase `sampleInterval` per CollectEntry
- Batch database inserts
- Use buffering/throttling strategies

### 3. **Memory Leaks in Streams**

**Issue:** Stream subscriptions not properly cancelled.

**Locations:**
- [state_man.dart:636-694](lib/core/state_man.dart#L636-L694) - AutoDisposingStream
- [collector.dart:232-294](lib/core/collector.dart#L232-L294) - collectStream

**Debug:**
- Use DevTools Memory tab to find growing collections
- Check for listeners not being cleaned up
- Verify `_idleTimer` is triggering in AutoDisposingStream

### 4. **Tight Loop in runIterate**

**Issue:** The OPC UA client runs in a tight loop with only 10ms delay.

**Location:** [state_man.dart:243-246](lib/core/state_man.dart#L243-L246)

```dart
while (clientref.runIterate(const Duration(milliseconds: 10)) && _shouldRun) {
  await Future.delayed(const Duration(milliseconds: 10));
}
```

**Debug:**
- Profile CPU usage in DevTools
- Check if increasing the delay helps

**Fix Options:**
- Increase delay to 50-100ms if responsiveness allows
- Use event-driven approach instead of polling

### 5. **Historical Data Query Load**

**Issue:** Loading large historical datasets on stream listen.

**Location:** [collector.dart:275-276](lib/core/collector.dart#L275-L276)

**Debug:**
- Log query time and result count
- Check database query performance
- Monitor memory growth when streams are created

**Fix Options:**
- Limit historical data window
- Paginate results
- Add database indexes

## DevTools Profiling Workflow

### CPU Profiling

1. Open DevTools → Performance tab
2. Click "Record"
3. Run your workload for 30-60 seconds
4. Click "Stop"
5. Look for:
   - Hot methods (high % of CPU time)
   - Deep call stacks
   - Unexpected heavy operations

### Memory Profiling

1. Open DevTools → Memory tab
2. Take a snapshot
3. Run your workload
4. Take another snapshot
5. Compare snapshots to find:
   - Growing collections (List, Map, Queue)
   - Leaked subscriptions (StreamSubscription)
   - Retained objects that should be GC'd

### Timeline Analysis

1. Open DevTools → Timeline tab
2. Record timeline
3. Look for:
   - Frame drops (if UI involved)
   - Long async gaps
   - GC pressure (frequent collection events)

## Command-Line Profiling

### Memory Usage Monitoring

```bash
# macOS/Linux
watch -n 1 'ps aux | grep "dart.*main.dart"'

# Or use built-in resource monitor
dart run bin/main.dart
```

### VM Flags for Debugging

Add to launch.json `vmAdditionalArgs`:

```json
"vmAdditionalArgs": [
  "--observe",                    // Enable DevTools
  "--pause-isolates-on-exit",    // Pause before exit
  "--enable-vm-service",         // Enable VM service
  "--disable-service-auth-codes" // Easier connection (dev only!)
]
```

## Logging Best Practices

Add strategic logging to track resource usage:

```dart
// Track subscription lifecycle
logger.d('Subscriptions active: ${_subscriptions.length}');

// Track database operations
final stopwatch = Stopwatch()..start();
await database.insertTimeseriesData(...);
logger.d('DB insert took ${stopwatch.elapsedMilliseconds}ms');

// Track stream listeners
logger.d('Stream listeners: $_listenerCount for key: $key');
```

## Specific Checks for Your Code

### Check 1: Subscription Growth

Add to StateMan:

```dart
Timer.periodic(Duration(seconds: 30), (_) {
  logger.i('Active subscriptions: ${_subscriptions.length}');
  for (final key in _subscriptions.keys) {
    logger.d('  - $key');
  }
});
```

### Check 2: Database Write Rate

Add to Collector:

```dart
int _writeCount = 0;
Timer.periodic(Duration(seconds: 10), (_) {
  logger.i('DB writes/sec: ${_writeCount / 10}');
  _writeCount = 0;
});

// In insertValue:
_writeCount++;
```

### Check 3: OPC UA Traffic

The open62541 client itself may be chatty. Check network traffic:

```bash
# Monitor network connections
netstat -an | grep 4840

# Or use tcpdump to see OPC UA traffic
sudo tcpdump -i any port 4840
```

## Known Issues in Current Code

1. **No backpressure handling** in collector streams ([collector.dart:250-274](lib/core/collector.dart#L250-L274))
2. **Queue growth unbounded** in collectStream ([collector.dart:242](lib/core/collector.dart#L242))
3. **Timer not cancelled** on error in collector ([collector.dart:179](lib/core/collector.dart#L179))
4. **Retry loop has no backoff** in _monitor ([collector.dart:586-632](lib/core/state_man.dart#L586-L632))

## Next Steps

1. Run with profile launch configuration
2. Add ResourceMonitor to main.dart
3. Connect DevTools and take baseline measurements
4. Run workload and identify hotspots
5. Address specific issues based on profiling data

## Additional Resources

- [Dart DevTools](https://dart.dev/tools/dart-devtools)
- [Dart Performance Best Practices](https://dart.dev/guides/language/performance)
- [RxDart Performance](https://pub.dev/packages/rxdart#performance)
