import 'dart:convert';

import 'package:mcp_dart/mcp_dart.dart';

import '../safety/risk_gate.dart';
import '../services/asset_type_catalog.dart';
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

/// Valid asset_name values for AssetRegistry.parse, derived from
/// [AssetTypeCatalog] -- the package's single description of the asset
/// types the Flutter-side registry can instantiate. The app-layer test
/// test/mcp/asset_type_sync_test.dart fails when the catalog and
/// AssetRegistry diverge.
final List<String> kValidAssetTypes = List.unmodifiable(
  AssetTypeCatalog.all.map((t) => t.assetName),
);

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

  registry.registerTool(
    name: 'update_asset',
    description: 'Propose changing fields on an asset that already exists '
        'on a page. The target is matched when the proposal is applied, by '
        'asset_type narrowed by title and/or key -- the match must be '
        'unique or nothing is changed. Returns proposal JSON for the page '
        'editor -- does not write to the database.',
    inputSchema: JsonSchema.object(
      properties: {
        'page_key': JsonSchema.string(
          description: 'Key of the page holding the asset (e.g., "/")',
        ),
        'asset_type': JsonSchema.string(
          description: 'Type name of the target asset. '
              'All valid types: ${kValidAssetTypes.join(", ")}',
        ),
        'title': JsonSchema.string(
          description: 'Display label of the target asset, to narrow the '
              'match when several assets share the type',
        ),
        'key': JsonSchema.string(
          description: 'Tag key currently bound to the target asset, to '
              'narrow the match',
        ),
        'child_id': JsonSchema.string(
          description: 'Stable id of a child entry inside the target '
              '(e.g. a ThirdPartyEquipment or Elevator child). When set, '
              'the patch applies to that child instead of the asset itself.',
        ),
        'patch': JsonSchema.object(
          description: 'Fields to change, shallow-merged onto the asset\'s '
              'JSON. Keys match the asset type\'s serialization fields, '
              'e.g. {"key": "SB1.Running"} rebinds the tag, {"text": '
              '"Infeed"} relabels. The asset\'s type cannot be changed.',
        ),
      },
      required: ['page_key', 'asset_type', 'patch'],
    ),
    handler: (args, extra) async {
      final pageKey = args['page_key'] as String;
      final assetType = args['asset_type'] as String;
      final title = args['title'] as String?;
      final key = args['key'] as String?;
      final childId = args['child_id'] as String?;
      final patch = args['patch'];

      if (!kValidAssetTypes.contains(assetType)) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'Unknown asset_type "$assetType". '
                  'Valid types: ${kValidAssetTypes.join(", ")}',
            ),
          ],
          isError: true,
        );
      }
      if (patch is! Map<String, dynamic> || patch.isEmpty) {
        return CallToolResult(
          content: [TextContent(text: 'patch must be a non-empty object')],
          isError: true,
        );
      }

      final targetLabel = title ?? key ?? assetType;
      final proposal = <String, dynamic>{
        // Top-level title is what ProposalService records and the
        // notification banner shows.
        'title': 'Update $targetLabel',
        'page_key': pageKey,
        'target': {
          'asset_type': assetType,
          if (title != null) 'title': title,
          if (key != null) 'key': key,
          if (childId != null) 'child_id': childId,
        },
        'patch': patch,
      };

      final diff = proposalService.formatCreateDiff('Asset Update', targetLabel, {
        'page': pageKey,
        'target': [
          assetType,
          if (title != null) 'title "$title"',
          if (key != null) 'key "$key"',
          if (childId != null) 'child "$childId"',
        ].join(', '),
        for (final e in patch.entries) 'patch: ${e.key}': '${e.value}',
      });

      // Elicit -- ProposalDeclinedException propagates to middleware
      await riskGate.requestConfirmation(
        description: 'Update asset: $targetLabel',
        level: RiskLevel.medium,
        details: {'diff': diff},
      );

      final wrapped = proposalService.wrapProposal('asset_update', proposal);
      return CallToolResult(
        content: [TextContent(text: jsonEncode(wrapped))],
      );
    },
  );
}
