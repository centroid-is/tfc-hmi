import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../safety/risk_gate.dart';
import '../services/proposal_service.dart';
import 'tool_registry.dart';

/// Slugifies a title into a URL-safe key with the given prefix.
String _slugify(String prefix, String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');
  return '$prefix-$slug';
}

/// Valid asset_name values for AssetRegistry.parse. Each maps to a factory
/// in registry.dart. The LLM must use one of these as `asset_type`.
const List<String> kValidAssetTypes = [
  'LEDConfig',
  'ButtonConfig',
  'NumberConfig',
  'TextAssetConfig',
  'IconConfig',
  'DrawnBoxConfig',
  'ArrowConfig',
  'LEDColumnConfig',
  'ConveyorConfig',
  'ConveyorColorPaletteConfig',
  'GraphAssetConfig',
  'RatioNumberConfig',
  'BpmConfig',
  'RateValueConfig',
  'AnalogBoxConfig',
  'OptionVariableConfig',
  'TableAssetConfig',
  'StartStopPillButtonConfig',
  'DrawingViewerConfig',
  'GateStatusConfig',
];

/// Registers the propose_asset MCP write tool.
///
/// This tool generates an asset hierarchy proposal with parent/child
/// relationships. It returns proposal JSON for the Flutter layer to route
/// to the asset editor -- it never writes to the database.
void registerAssetWriteTools({
  required ToolRegistry registry,
  required RiskGate riskGate,
  required ProposalService proposalService,
}) {
  registry.registerTool(
    name: 'propose_asset',
    description: 'Create an asset hierarchy proposal with parent/child '
        'relationships. Returns proposal JSON for the asset editor -- does '
        'not write to the database.',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(
          description: 'Asset group name (e.g., "Pump Station")',
        ),
        'page_key': JsonSchema.string(
          description: 'Key of the page to add assets to (e.g., "/"). '
              'If omitted, assets are added to the current page.',
        ),
        'children': JsonSchema.array(
          description: 'Child assets in the hierarchy',
          items: JsonSchema.object(
            properties: {
              'asset_type': JsonSchema.string(
                description: 'Asset type name. Common types: '
                    'LEDConfig (status indicator), '
                    'ButtonConfig (clickable button), '
                    'NumberConfig (numeric value display), '
                    'TextAssetConfig (text label), '
                    'IconConfig (icon display), '
                    'DrawnBoxConfig (colored box), '
                    'GraphAssetConfig (time-series graph). '
                    'All valid types: ${kValidAssetTypes.join(", ")}',
              ),
              'key': JsonSchema.string(
                description:
                    'PLC tag key to bind to (e.g., "pump3.speed")',
              ),
              'title': JsonSchema.string(
                description: 'Display label (e.g., "Pump 3 Speed")',
              ),
              'x': JsonSchema.number(
                description:
                    'Horizontal position as a fraction of page width (0.0 = left, 1.0 = right). '
                    'Defaults to 0.1 if omitted.',
              ),
              'y': JsonSchema.number(
                description:
                    'Vertical position as a fraction of page height (0.0 = top, 1.0 = bottom). '
                    'Defaults to 0.1 if omitted.',
              ),
              'config': JsonSchema.object(
                description:
                    'Optional asset configuration overrides. Keys match '
                    'the asset type\'s JSON serialization fields. For '
                    'example, ButtonConfig supports: '
                    '"outward_color", "inward_color" (objects with '
                    'r/g/b/a 0-255), "button_type" ("circle"|"square"), '
                    '"is_toggle" (bool), "text" (label string), '
                    '"text_pos" ("above"|"below"|"left"|"right"|"inside"). '
                    'NumberConfig supports: "suffix" (unit string). '
                    'LEDConfig supports: "on_color", "off_color". '
                    'Any field the asset\'s toJson() produces can be set '
                    'here. Unknown keys are silently ignored.',
              ),
            },
            required: ['asset_type', 'key', 'title'],
          ),
        ),
      },
      required: ['title', 'children'],
    ),
    handler: (args, extra) async {
      final title = args['title'] as String;
      final rawChildren = args['children'] as List<dynamic>;
      final pageKey = args['page_key'] as String?;

      // Build children list with asset_name for AssetRegistry.parse
      final children = rawChildren.map((c) {
        final child = c as Map<String, dynamic>;
        final assetType = child['asset_type'] as String;
        final entry = <String, dynamic>{
          'asset_name': assetType,
          'key': child['key'],
          'title': child['title'],
        };
        // Pass through position if provided.
        if (child['x'] is num) entry['x'] = child['x'];
        if (child['y'] is num) entry['y'] = child['y'];
        // Pass through config overrides if provided.
        if (child['config'] is Map<String, dynamic>) {
          entry['config'] = child['config'];
        }
        return entry;
      }).toList();

      // Build proposal
      final key = _slugify('asset', title);
      final proposal = <String, dynamic>{
        'key': key,
        'title': title,
        'children': children,
        if (pageKey != null) 'page_key': pageKey,
      };

      // Format hierarchy diff for elicitation
      final hierarchyLines = children.isEmpty
          ? '(no children)'
          : children
              .map((c) =>
                  '  - ${c['asset_name']} "${c['title']}" → ${c['key']}')
              .join('\n');
      final diff = proposalService.formatCreateDiff('Asset', title, {
        'key': key,
        'title': title,
        'children': '\n$hierarchyLines',
      });

      // Elicit -- ProposalDeclinedException propagates to middleware
      await riskGate.requestConfirmation(
        description: 'Create asset: $title',
        level: RiskLevel.medium,
        details: {'diff': diff},
      );

      final wrapped = proposalService.wrapProposal('asset', proposal);
      return CallToolResult(
        content: [TextContent(text: jsonEncode(wrapped))],
      );
    },
  );
}
