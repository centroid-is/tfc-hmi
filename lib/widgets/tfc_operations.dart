import 'package:flutter/material.dart';
import 'package:tfc_hmi/widgets/base_scaffold.dart';
import 'package:tfc_hmi/dbus/generated/operations.dart';
import 'package:dbus/dbus.dart';

class IndustrialAppBarLeftWidgetProvider
    extends GlobalAppBarLeftWidgetProvider {
  bool _isRunning = false;
  late final IsCentroidOperationMode _operationMode;

  IndustrialAppBarLeftWidgetProvider(DBusClient client) {
    _operationMode = IsCentroidOperationMode(
        client,
        'is.centroid.operations.def',
        DBusObjectPath('/is/centroid/OperationMode'));

    // Listen for mode updates
    _operationMode.update.listen((update) {
      _isRunning = update.new_mode != 'stopped';
      notifyListeners();
    });

    // Initialize current state
    _operationMode.getMode().then((mode) {
      _isRunning = mode != 'stopped';
      notifyListeners();
    });
  }

  bool get isRunning => _isRunning;

  Future<void> toggleRunning() async {
    try {
      if (_isRunning) {
        await _operationMode.callSetMode('stopped');
      } else {
        await _operationMode.callSetMode('running');
      }
    } catch (e) {
      debugPrint('Failed to toggle operation mode: $e');
    }
  }

  @override
  Widget buildAppBarLeftWidgets(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play / Stop toggle button.
        IconButton(
          icon: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
          tooltip: _isRunning ? 'Stop' : 'Start',
          onPressed: () {
            toggleRunning();
          },
        ),
        // Cleaning icon button.
        IconButton(
          icon: const Icon(Icons.cleaning_services),
          tooltip: 'Cleaning',
          onPressed: () {
            // Insert your cleaning logic here.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cleaning started')),
            );
          },
        ),
        // Show current run state.
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              _isRunning ? 'Running' : 'Stopped',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFamily: 'roboto-mono',
                    fontSize: 16.0,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.1,
                    height: 1.5,
                  ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              locale: const Locale('en', 'US'),
            ),
          ),
        ),
      ],
    );
  }
}
