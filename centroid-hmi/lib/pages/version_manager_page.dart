import 'package:flutter/material.dart';
import 'package:centroidx_upgrader/centroidx_upgrader.dart';

class VersionManagerPage extends StatefulWidget {
  final ManagerLauncher launcher;
  const VersionManagerPage({super.key, required this.launcher});
  @override
  State<VersionManagerPage> createState() => _VersionManagerPageState();
}

class _VersionManagerPageState extends State<VersionManagerPage> {
  String _status = 'Opening version manager...';

  @override
  void initState() {
    super.initState();
    _launchManager();
  }

  Future<void> _launchManager() async {
    try {
      final pid = await widget.launcher.launchForPicker();
      if (mounted) {
        setState(() {
          _status = 'Version manager opened (PID: $pid).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Failed to open version manager: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Version Manager')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.update, size: 48),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              const Text(
                'The version manager handles version selection and installation.\n'
                'Close the version manager window when done.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
