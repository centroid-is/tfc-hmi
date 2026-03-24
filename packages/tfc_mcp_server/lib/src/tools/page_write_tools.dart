import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../safety/risk_gate.dart';
import '../services/proposal_service.dart';
import 'asset_write_tools.dart' show kValidAssetTypes;
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

/// Registers the propose_page MCP write tool.
///
/// This tool generates an HMI page layout proposal with assets, key bindings,
/// and layout positioning. It returns proposal JSON for the Flutter layer to
/// route to the page editor -- it never writes to the database.
void registerPageWriteTools({
  required ToolRegistry registry,
  required RiskGate riskGate,
  required ProposalService proposalService,
}) {
  registry.registerTool(
    name: 'propose_page',
    description: 'Create an HMI page layout proposal with assets and key '
        'bindings. Returns proposal JSON for the page editor -- does not '
        'write to the database. Each asset must specify an asset_type from '
        'the valid types list so the app can instantiate it.',
    inputSchema: JsonSchema.object(
      properties: {
        'title': JsonSchema.string(
          description: 'Page title (e.g., "Pump Overview")',
        ),
        'assets': JsonSchema.array(
          description: 'Asset definitions for the page layout',
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
              'label': JsonSchema.string(
                description: 'Display label for the asset',
              ),
              'x': JsonSchema.number(
                description:
                    'X position as fraction 0.0-1.0 of page width',
              ),
              'y': JsonSchema.number(
                description:
                    'Y position as fraction 0.0-1.0 of page height',
              ),
            },
            required: ['asset_type', 'key'],
          ),
        ),
      },
      required: ['title', 'assets'],
    ),
    handler: (args, extra) async {
      final title = args['title'] as String;
      final rawAssets = args['assets'] as List<dynamic>;

      // Build asset list with asset_name for AssetRegistry.parse
      final assets = rawAssets.map((a) {
        final asset = a as Map<String, dynamic>;
        final assetType = asset['asset_type'] as String;
        final built = <String, dynamic>{
          'asset_name': assetType,
          'key': asset['key'],
        };
        if (asset['label'] != null) {
          built['text'] = asset['label'];
        }
        if (asset['x'] != null || asset['y'] != null) {
          built['coordinates'] = {
            'x': (asset['x'] as num?)?.toDouble() ?? 0.1,
            'y': (asset['y'] as num?)?.toDouble() ?? 0.1,
          };
        }
        // TextAssetConfig uses 'textContent' instead of 'key'
        if (assetType == 'TextAssetConfig') {
          built['textContent'] = asset['label'] ?? asset['key'] ?? '';
        }
        return built;
      }).toList();

      // Build proposal
      final key = _slugify('page', title);
      final proposal = <String, dynamic>{
        'key': key,
        'title': title,
        'assets': assets,
      };

      // Format diff for elicitation
      final assetSummary = assets.isEmpty
          ? 'no assets'
          : '${assets.length} asset(s): '
              '${assets.map((a) => a['asset_name']).join(', ')}';
      final diff = proposalService.formatCreateDiff('Page', title, {
        'key': key,
        'title': title,
        'assets': assetSummary,
      });

      // Elicit -- ProposalDeclinedException propagates to middleware
      await riskGate.requestConfirmation(
        description: 'Create page: $title',
        level: RiskLevel.medium,
        details: {'diff': diff},
      );

      final wrapped = proposalService.wrapProposal('page', proposal);
      return CallToolResult(
        content: [TextContent(text: jsonEncode(wrapped))],
      );
    },
  );
}
