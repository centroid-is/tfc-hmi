import 'dart:async';

// TODO this should be a opc ua compliant status code, should come from the opcua lib
class OPCUAError extends Error {
  final String message;
  OPCUAError(this.message);
  @override
  String toString() => 'OPCUAError: $message';
}

class StateMan {
  /// Constructor requires the server endpoint.
  StateMan(this.endpointUrl);

  bool get isConnected => _connected;
  bool _connected = false;
  final String endpointUrl;

  /// Example: read<int>("myKey") or read<String>("myStringKey")
  Future<T> read<T>(String key) async {
    if (!_connected) {
      throw OPCUAError('Not connected to server');
    }
    try {
      print('Reading value of key: $key');
      await Future.delayed(Duration(milliseconds: 500));

      // Return type-specific dummy data
      if (T == int) {
        return 42 as T;
      } else if (T == double) {
        return 42.0 as T;
      } else if (T == bool) {
        return true as T;
      } else if (T == String) {
        return 'stub-value-of-$key' as T;
      } else {
        throw OPCUAError('Unsupported type: $T');
      }
    } catch (e) {
      throw OPCUAError('Failed to read key: $e');
    }
  }

  /// Example: write<int>("myKey", 42) or write<String>("myStringKey", "hello")
  Future<void> write<T>(String key, T value) async {
    if (!_connected) {
      throw OPCUAError('Not connected to server');
    }
    try {
      print('Writing value "$value" to nodeId: $key');
      await Future.delayed(Duration(milliseconds: 500));
    } catch (e) {
      throw OPCUAError('Failed to write node: $e');
    }
  }

  /// Subscribe to data changes on a specific node with type safety.
  /// Returns a Stream that can be cancelled to stop the subscription.
  /// Example: subscribe<int>("myIntKey") or subscribe<String>("myStringKey")
  Future<Stream<T>> subscribe<T>(String key) async {
    if (!_connected) {
      throw OPCUAError('Cannot subscribe to node. Not connected to server.');
    }

    final controller = StreamController<T>.broadcast();
    controller.onCancel = () async {
      // Cleanup when the last listener unsubscribes
      print('Unsubscribing from key: $key');
      await _handleUnsubscribe(key);
      await controller.close();
    };

    try {
      print('Subscribing to data changes for key: $key');
      await _handleSubscribe(key);
      bool bool_last_value = false;
      int int_last_value = 0;
      double double_last_value = 0.0;

      // For demonstration, simulate periodic updates
      Timer.periodic(Duration(seconds: 2), (timer) {
        if (controller.isClosed) {
          timer.cancel();
          return;
        }
        if (!_connected) {
          timer.cancel();
          controller.close();
          return;
        }

        // Simulate data updates (replace with actual OPC UA data)
        if (T == int) {
          controller.add(int_last_value++ as T);
        } else if (T == String) {
          controller.add('Updated value at ${DateTime.now()}' as T);
        } else if (T == double) {
          controller.add(double_last_value++ as T);
        } else if (T == bool) {
          controller.add(bool_last_value as T);
          bool_last_value = !bool_last_value;
        } else {
          print('Unsupported type: $T');
        }
      });

      return controller.stream;
    } catch (e) {
      await controller.close();
      throw OPCUAError('Failed to subscribe: $e');
    }
  }

  // Internal methods to handle actual OPC UA subscription
  Future<void> _handleSubscribe(String nodeId) async {
    // In real implementation: Create actual OPC UA subscription
    await Future.delayed(Duration(milliseconds: 500));
  }

  Future<void> _handleUnsubscribe(String nodeId) async {
    // In real implementation: Delete actual OPC UA subscription
    await Future.delayed(Duration(milliseconds: 500));
  }
}
