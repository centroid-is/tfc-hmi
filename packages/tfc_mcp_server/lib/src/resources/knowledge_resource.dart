import 'package:mcp_dart/mcp_dart.dart';

/// Static description of how the TFC HMI application works internally.
///
/// This content grounds the AI copilot in system architecture, data models,
/// and capability boundaries so it can give accurate, contextual answers
/// to operator questions without hallucinating about what it can or cannot do.
const _knowledgeText = '''
# TFC HMI System Architecture

## System Components

### StateMan (State Manager)
Real-time state engine routing OPC UA subscriptions to the UI. Maintains a
key-value store of all live process values. Keys are logical names (e.g.,
"pump3.speed", "conveyor.belt_running") that map to OPC UA nodes via
KeyMappings. The AI can READ current values but CANNOT write or modify them.

### AlarmMan (Alarm Manager)
Rule-based alarm system. Each alarm has a UID, title, description, severity
level, and one or more rules defined as boolean expressions over tag values.
When a rule evaluates to true, the alarm activates. Operators can acknowledge
and snooze alarms. The AI can READ alarm state, history, and definitions but
CANNOT acknowledge, silence, or modify alarms.

### Collector
Configurable data collection service that samples tag values at defined
intervals and stores them as timeseries in PostgreSQL. Used for trend
analysis and historical queries. Retention policies control data lifetime.

### PageManager
Dynamic HMI page builder. Pages contain positioned widgets (LEDs, buttons,
graphs, conveyors, Beckhoff terminals, etc.) bound to keys. Pages are
organized as assets in a hierarchy. The AI can READ page and asset
configuration but CANNOT modify layouts directly.

## Data Models

### Key Mappings
Key mappings bind logical key names to OPC UA node addresses.
Format: logical_key -> {namespace, identifier}
Example: "pump3.speed" -> ns=2;s=Pump3.Speed
The AI always works with logical key names, never raw OPC UA node IDs.

### Alarm Definitions
Each alarm definition contains: UID (unique identifier), key (the tag it
monitors), title, description, severity level, and rules (boolean expressions).
Boolean expressions use operators: AND, OR, NOT, >, <, >=, <=, ==, !=
Example: "pump3.overcurrent > 15 AND pump3.running == true"

### Pages and Assets
Pages are HMI display screens containing widgets. Each page has a key (unique
identifier) and title. Assets represent physical equipment or logical groups
in the plant hierarchy. Pages are often associated with assets.

## AI Capabilities and Boundaries

### What the AI CAN do:
- Read live tag values from StateMan
- Read alarm configuration, active alarms, and alarm history
- Read system configuration (pages, assets, key mappings, alarm definitions)
- Search electrical drawings by component name
- Generate configuration proposals (alarms, key mappings, pages, assets)
- Explain why alarms fired using correlated data
- Produce shift handover summaries

### What the AI CANNOT do:
- Write to OPC UA (no control of physical equipment)
- Write directly to the database (all changes go through HMI editors)
- Modify StateMan values
- Acknowledge or silence alarms
- Control or override safety systems
- Access encrypted server configurations (OPC UA endpoints, DB credentials)

### How Proposals Work
When the AI suggests a configuration change, it generates a proposal that
opens in the appropriate HMI editor (alarm editor, key repository, page
editor). The operator reviews and saves -- the AI never commits changes.
''';

/// Registers the `scada://source/knowledge` resource on [mcpServer].
///
/// This resource returns a static description of how the TFC HMI application
/// works internally -- system components, data models, and AI capabilities.
/// It has no service dependencies and is always available.
void registerKnowledgeResource(McpServer mcpServer) {
  mcpServer.registerResource(
    'Application Knowledge',
    'scada://source/knowledge',
    (
      description:
          'How the TFC HMI application works internally -- system components, '
          'data models, and AI capabilities',
      mimeType: 'text/plain',
    ),
    (Uri uri, RequestHandlerExtra extra) async {
      return ReadResourceResult(
        contents: [
          TextResourceContents(
            uri: uri.toString(),
            mimeType: 'text/plain',
            text: _knowledgeText,
          ),
        ],
      );
    },
  );
}
