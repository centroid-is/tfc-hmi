import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _integrationDir = '${Directory.current.path}/test/integration';

/// Manages a Python Modbus test server process for integration tests.
///
/// The server communicates via stdin/stdout using a simple text protocol:
///   - Commands are sent as lines to stdin
///   - Responses are read as lines from stdout
///   - The server emits `READY` on stdout when it is ready to accept connections
class ModbusTestServerProcess {
  Process? _process;
  final int port;
  final String _venvDir;

  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  final List<String> _stdoutLines = [];
  Completer<void>? _responseCompleter;

  ModbusTestServerProcess({this.port = 5020})
      : _venvDir = '$_integrationDir/.venv';

  /// Ensures the Python virtual environment exists and dependencies are installed.
  static Future<void> ensureVenv() async {
    final venvPython = '$_integrationDir/.venv/bin/python3';

    if (await File(venvPython).exists()) {
      print('Python venv already exists');
      return;
    }

    print('Creating Python venv...');
    final venvResult = await Process.run(
      'python3',
      ['-m', 'venv', '.venv'],
      workingDirectory: _integrationDir,
    );

    if (venvResult.exitCode != 0) {
      throw Exception('Failed to create Python venv: ${venvResult.stderr}');
    }

    print('Installing Python dependencies...');
    final pipResult = await Process.run(
      '.venv/bin/pip',
      ['install', '-r', 'requirements.txt'],
      workingDirectory: _integrationDir,
    );

    if (pipResult.exitCode != 0) {
      throw Exception(
          'Failed to install Python dependencies: ${pipResult.stderr}');
    }

    print('Python venv created and dependencies installed');
  }

  /// Starts the Modbus test server process and waits for it to be ready.
  Future<void> start() async {
    if (_process != null) {
      throw StateError('Modbus test server is already running');
    }

    if (!await File('$_venvDir/bin/python3').exists()) {
      await ensureVenv();
    }

    print('Starting Modbus test server on port $port...');

    _process = await Process.start(
      '.venv/bin/python3',
      ['modbus_server.py', '--port', port.toString()],
      workingDirectory: _integrationDir,
    );

    final readyCompleter = Completer<void>();

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      print('[modbus-server stdout] $line');

      if (!readyCompleter.isCompleted && line.trim() == 'READY') {
        readyCompleter.complete();
        return;
      }

      // Buffer response lines for command/response protocol
      _stdoutLines.add(line);
      if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
        _responseCompleter!.complete();
      }
    });

    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      print('[modbus-server stderr] $line');
    });

    // Wait for the READY signal with a timeout
    try {
      await readyCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
              'Modbus test server did not become ready within 10 seconds');
        },
      );
    } catch (e) {
      await stop();
      rethrow;
    }

    print('Modbus test server is ready on port $port');
  }

  /// Sends a command to the server process via stdin.
  Future<void> _sendCommand(String command) async {
    if (_process == null) {
      throw StateError('Modbus test server is not running');
    }

    _process!.stdin.writeln(command);
    await _process!.stdin.flush();
  }

  /// Sends a command and waits for a response line on stdout.
  Future<String> _sendCommandWithResponse(String command) async {
    if (_process == null) {
      throw StateError('Modbus test server is not running');
    }

    // Create a fresh completer and clear buffered lines
    _responseCompleter = Completer<void>();
    _stdoutLines.clear();

    _process!.stdin.writeln(command);
    await _process!.stdin.flush();

    // Poll for a response with timeout
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (_stdoutLines.isNotEmpty) {
        final line = _stdoutLines.removeAt(0);
        _responseCompleter = null;
        return line;
      }

      // Wait for the next line or a short timeout
      _responseCompleter ??= Completer<void>();
      try {
        await _responseCompleter!.future.timeout(
          const Duration(milliseconds: 500),
        );
      } on TimeoutException {
        // Retry the check
      }
      _responseCompleter = null;
    }

    throw TimeoutException(
        'Modbus test server did not respond to "$command" within 10 seconds');
  }

  // ---------------------------------------------------------------------------
  // Register manipulation methods
  // ---------------------------------------------------------------------------

  /// Sets a holding register value at the given address.
  Future<void> setHoldingRegister(int address, int value) async {
    await _sendCommand('SET HR $address $value');
  }

  /// Sets an input register value at the given address.
  Future<void> setInputRegister(int address, int value) async {
    await _sendCommand('SET IR $address $value');
  }

  /// Sets a coil value at the given address.
  Future<void> setCoil(int address, bool value) async {
    await _sendCommand('SET CO $address ${value ? 1 : 0}');
  }

  /// Sets a discrete input value at the given address.
  Future<void> setDiscreteInput(int address, bool value) async {
    await _sendCommand('SET DI $address ${value ? 1 : 0}');
  }

  /// Reads a holding register value at the given address.
  Future<int> getHoldingRegister(int address) async {
    final response = await _sendCommandWithResponse('GET HR $address');
    return int.parse(response.trim());
  }

  /// Reads a coil value at the given address.
  Future<bool> getCoil(int address) async {
    final response = await _sendCommandWithResponse('GET CO $address');
    return response.trim() == '1';
  }

  /// Stops the Modbus test server process.
  Future<void> stop() async {
    if (_process == null) {
      return;
    }

    print('Stopping Modbus test server...');

    try {
      _process!.stdin.writeln('STOP');
      await _process!.stdin.flush();

      // Wait for the process to exit gracefully
      final exitCode = await _process!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('Modbus test server did not exit gracefully, killing...');
          _process!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );

      print('Modbus test server stopped (exit code: $exitCode)');
    } catch (e) {
      print('Error stopping Modbus test server: $e');
      _process?.kill(ProcessSignal.sigkill);
    } finally {
      await _stdoutSub?.cancel();
      await _stderrSub?.cancel();
      _stdoutSub = null;
      _stderrSub = null;
      _process = null;
      _stdoutLines.clear();
      _responseCompleter = null;
    }
  }
}
