# TFC Core - Pure Dart Package

A pure Dart package extracted from the TFC HMI application for headless data collection.

## Overview

This package contains the core business logic for the TFC (Time For Change) industrial HMI system, refactored to run as a pure Dart application without Flutter dependencies. This enables better performance for headless data collection scenarios.

## Features

- **Isolate-based Architecture**: One isolate per OPC UA server for optimal parallel performance
- **OPC UA Communication**: Connect to multiple OPC UA servers and subscribe to data points
- **Timeseries Data Collection**: Collect and store data to PostgreSQL with configurable sampling rates
- **Alarm Management**: Evaluate boolean expressions and trigger alarms based on conditions
- **Database Integration**: PostgreSQL and SQLite support via Drift ORM
- **Secure Configuration**: Linux keychain integration for sensitive credentials
- **File-based Preferences**: Simple JSON-based preferences for configuration
- **TUI Configuration Tool**: Simple terminal UI for easy setup without Flutter

## Architecture

```
lib/core/
├── alarm.dart              # Alarm management system
├── boolean_expression.dart # Expression parser and evaluator
├── collector.dart          # Data collection and sampling
├── database.dart           # High-level database abstraction
├── database_drift.dart     # Drift ORM schema and implementation
├── file_preferences.dart   # File-based preferences (replaces SharedPreferences)
├── preferences.dart        # Unified preferences API
├── ring_buffer.dart        # Circular buffer for historical data
├── state_man.dart          # OPC UA state manager
└── secure_storage/         # Platform-specific secure storage
```

## Usage

### As a Library

Add to your `pubspec.yaml`:

```yaml
dependencies:
  tfc_core:
    path: ../packages/tfc_core
```

Then import:

```dart
import 'package:tfc_core/tfc_core.dart';
```

### As an Executable

The package includes two executables:

#### 1. Configuration Tool (TUI)

```bash
# Compile
dart compile exe bin/tfc_config.dart -o tfc_config

# Run interactively
./tfc_config
```

The TUI tool allows you to:
- Configure PostgreSQL or SQLite database
- Add/remove OPC UA servers
- Test database connections
- View current configuration

#### 2. Data Collector

```bash
# Compile
dart compile exe bin/tfc_collector.dart -o tfc_collector

# Run
./tfc_collector
```

The collector:
- Spawns one isolate per OPC UA server (optimal performance)
- Automatically reconnects on failures with exponential backoff
- Collects and stores timeseries data to database
- Runs headless without UI overhead

**Setup**: Configure using either:
1. The TUI tool: `./tfc_config`
2. The Flutter UI application (centroid-hmi) for advanced features

## Configuration Storage

- **Secure credentials**: Stored in Linux keychain via `amplify_secure_storage_dart`
- **Preferences**: Stored in `~/.config/tfc/preferences.json`
- **Database**: SQLite files in `~/.local/share/tfc/` (if not using PostgreSQL)

## Performance Benefits

Running as a pure Dart executable instead of Flutter in Weston headless mode provides:
- **Lower memory usage**: No UI framework overhead
- **Faster startup**: No rendering engine initialization
- **Better CPU efficiency**: Minimal dependencies
- **Smaller binary size**: ~15-20MB vs 50+MB for Flutter

## Development

```bash
# Get dependencies
dart pub get

# Generate code (Drift, JSON serialization)
dart run build_runner build --delete-conflicting-outputs

# Run tests
dart test

# Compile executable
dart compile exe bin/tfc_collector.dart -o tfc_collector
```

## Differences from Flutter Package

- Replaced `shared_preferences` with file-based `FilePreferences`
- Removed `path_provider`, using `Platform.environment['HOME']` directly
- Removed Flutter-specific converters (`color_converter.dart`, `icon.dart`)
- Simplified `secure_storage` to Linux-only implementation
- Using `drift` with native executor instead of `drift_flutter`

## License

Same as parent project.

## See Also

- Main Flutter UI: `../centroid-hmi/`
- Parent package: `../` (tfc)
