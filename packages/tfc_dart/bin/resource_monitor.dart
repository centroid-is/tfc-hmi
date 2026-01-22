import 'dart:async';
import 'dart:io';
import 'package:logger/logger.dart';

/// Helper class to monitor and log resource consumption
class ResourceMonitor {
  final Logger _logger;
  Timer? _monitorTimer;
  int _peakRss = 0;

  ResourceMonitor(this._logger);

  /// Start monitoring resources at the specified interval
  void start({Duration interval = const Duration(seconds: 5)}) {
    _monitorTimer = Timer.periodic(interval, (_) => _logResourceUsage());
    _logger.i('Resource monitoring started (interval: $interval)');
  }

  /// Stop monitoring
  void stop() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _logger.i('Resource monitoring stopped. Peak RSS: ${_formatBytes(_peakRss)}');
  }

  void _logResourceUsage() {
    final info = ProcessInfo.currentRss;

    if (info > _peakRss) {
      _peakRss = info;
    }

    _logger.d('RSS: ${_formatBytes(info)} | Peak: ${_formatBytes(_peakRss)}');
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
