import 'package:flutter_test/flutter_test.dart';
import 'package:tfc/chat/tool_filter.dart';

void main() {
  group('AiAction tool sets', () {
    test('debugAsset includes diagnostic read-only tools', () {
      final tools = toolsFor(AiAction.debugAsset)!;
      expect(tools, contains('get_tag_value'));
      expect(tools, contains('list_tags'));
      expect(tools, contains('query_alarm_history'));
      expect(tools, contains('list_alarms'));
      expect(tools, contains('query_trend_data'));
      // get_plc_code_block needed so LLM can fetch full source for blocks
      // listed in the pre-computed call graph.
      expect(tools, contains('get_plc_code_block'));

      // diagnose_asset removed: when context is pre-computed the LLM must
      // not re-run the composite diagnostic. When context is fully complete,
      // chat.dart overrides the filter to only {get_plc_code_block}.
      expect(tools, isNot(contains('diagnose_asset')));

      // Should NOT include write tools
      expect(tools, isNot(contains('create_alarm')));
      expect(tools, isNot(contains('update_alarm')));
      expect(tools, isNot(contains('propose_page')));
      expect(tools, isNot(contains('propose_asset')));
      expect(tools, isNot(contains('create_key_mapping')));
    });

    test('createAlarm includes alarm creation tools', () {
      final tools = toolsFor(AiAction.createAlarm)!;
      expect(tools, contains('create_alarm'));
      expect(tools, contains('list_tags'));
      expect(tools, contains('get_tag_value'));
      expect(tools, contains('list_alarm_definitions'));

      // Should NOT include update or page tools
      expect(tools, isNot(contains('update_alarm')));
      expect(tools, isNot(contains('propose_page')));
    });

    test('editAlarm includes update_alarm but not create_alarm', () {
      final tools = toolsFor(AiAction.editAlarm)!;
      expect(tools, contains('update_alarm'));
      expect(tools, isNot(contains('create_alarm')));
    });

    test('duplicateAlarm includes create_alarm but not update_alarm', () {
      final tools = toolsFor(AiAction.duplicateAlarm)!;
      expect(tools, contains('create_alarm'));
      expect(tools, isNot(contains('update_alarm')));
    });

    test('configureAsset includes key mapping write tools', () {
      final tools = toolsFor(AiAction.configureAsset)!;
      expect(tools, contains('create_key_mapping'));
      expect(tools, contains('update_key_mapping'));
      expect(tools, contains('list_tags'));
      expect(tools, contains('list_asset_types'));
    });

    test('explainAsset is read-only', () {
      final tools = toolsFor(AiAction.explainAsset)!;
      expect(tools, contains('list_asset_types'));
      expect(tools, contains('search_tech_docs'));
      expect(tools, contains('search_plc_code'));

      // No write tools
      expect(tools, isNot(contains('create_alarm')));
      expect(tools, isNot(contains('update_alarm')));
      expect(tools, isNot(contains('propose_page')));
      expect(tools, isNot(contains('propose_asset')));
      expect(tools, isNot(contains('create_key_mapping')));
      expect(tools, isNot(contains('update_key_mapping')));
    });

    test('describePage includes config read tools', () {
      final tools = toolsFor(AiAction.describePage)!;
      expect(tools, contains('get_asset_detail'));
      expect(tools, contains('list_assets'));
      expect(tools, contains('list_key_mappings'));
      expect(tools, contains('get_tag_value'));

      // No write tools
      expect(tools, isNot(contains('propose_page')));
    });

    test('improveLayout includes propose_page', () {
      final tools = toolsFor(AiAction.improveLayout)!;
      expect(tools, contains('propose_page'));
      expect(tools, contains('list_asset_types'));
      expect(tools, contains('get_asset_detail'));
    });

    test('duplicatePage and createPage include propose_page', () {
      final dpTools = toolsFor(AiAction.duplicatePage)!;
      expect(dpTools, contains('propose_page'));
      expect(dpTools, contains('list_asset_types'));

      final cpTools = toolsFor(AiAction.createPage)!;
      expect(cpTools, contains('propose_page'));
      expect(cpTools, contains('list_asset_types'));
    });

    test('showHistory includes alarm history and trend tools', () {
      final tools = toolsFor(AiAction.showHistory)!;
      expect(tools, contains('query_alarm_history'));
      expect(tools, contains('query_trend_data'));
      expect(tools, contains('list_alarms'));
      expect(tools, contains('get_tag_value'));
    });

    test('freeform returns null (all tools)', () {
      expect(toolsFor(AiAction.freeform), isNull);
    });

    test('explainAssetChip has same tools as explainAsset', () {
      final chipTools = toolsFor(AiAction.explainAssetChip)!;
      final menuTools = toolsFor(AiAction.explainAsset)!;
      expect(chipTools, equals(menuTools));
    });

    test('every action has a reasonable tool count (4-12)', () {
      for (final action in AiAction.values) {
        final tools = toolsFor(action);
        if (action == AiAction.freeform) {
          expect(tools, isNull, reason: '$action should return null');
        } else {
          expect(
            tools!.length,
            inInclusiveRange(4, 12),
            reason: '$action has ${tools.length} tools, expected 4-12',
          );
        }
      }
    });

    test('all tool names are valid MCP tool names', () {
      const allKnownTools = {
        'ping',
        'list_tags',
        'get_tag_value',
        'list_alarms',
        'get_alarm_detail',
        'query_alarm_history',
        'list_pages',
        'list_assets',
        'get_asset_detail',
        'list_key_mappings',
        'list_alarm_definitions',
        'search_drawings',
        'get_drawing_page',
        'search_plc_code',
        'get_plc_code_block',
        'search_tech_docs',
        'get_tech_doc_section',
        'query_trend_data',
        'create_alarm',
        'update_alarm',
        'create_key_mapping',
        'update_key_mapping',
        'propose_page',
        'propose_asset',
        'list_asset_types',
        'diagnose_asset',
      };

      for (final action in AiAction.values) {
        final tools = toolsFor(action);
        if (tools == null) continue;
        for (final tool in tools) {
          expect(
            allKnownTools,
            contains(tool),
            reason: '$action references unknown tool "$tool"',
          );
        }
      }
    });
  });

  group('detectActionFromMessage', () {
    test('detects debug asset from diagnostic prompt', () {
      const msg = 'Debug asset: pump3.speed\n\n'
          '[ASSET CONTEXT - already fetched]\n'
          'Type: Number\nKey: pump3.speed\n[END ASSET CONTEXT]\n'
          'Please investigate this asset.';
      expect(detectActionFromMessage(msg), AiAction.debugAsset);
    });

    test('detects edit alarm from update_alarm tool reference', () {
      const msg = 'Use the update_alarm tool to modify this alarm.\n\n'
          '[ALARM CONTEXT]\nUID: abc-123\n[END ALARM CONTEXT]\n'
          '[describe what you want to change]';
      expect(detectActionFromMessage(msg), AiAction.editAlarm);
    });

    test('detects duplicate alarm from create_alarm + ALARM CONTEXT', () {
      const msg = 'Use the create_alarm tool to create a new alarm similar '
          'to this one.\n\n'
          '[ALARM CONTEXT]\nUID: abc-123\n[END ALARM CONTEXT]\n'
          '[describe what should be different]';
      expect(detectActionFromMessage(msg), AiAction.duplicateAlarm);
    });

    test('detects create alarm from create_alarm tool without context', () {
      const msg = 'Use the create_alarm tool to create an alarm that '
          "[describe what should trigger the alarm, e.g. 'activates "
          "when pump pressure exceeds 50 bar']";
      expect(detectActionFromMessage(msg), AiAction.createAlarm);
    });

    test('detects configure asset from Help me configure prefix', () {
      const msg = 'Help me configure asset "pump3.speed".\n\n'
          '[ASSET CONTEXT]\nType: Number\n[END ASSET CONTEXT]\n'
          'Suggest improvements.';
      expect(detectActionFromMessage(msg), AiAction.configureAsset);
    });

    test('detects explain asset from Explain the prefix', () {
      const msg = 'Explain the "Number" asset type.\n\n'
          '[ASSET CONTEXT]\nType: Number\n[END ASSET CONTEXT]';
      expect(detectActionFromMessage(msg), AiAction.explainAsset);
    });

    test('detects describe page', () {
      const msg =
          'Describe page "Pump Overview" (key: pump-overview) — what assets?';
      expect(detectActionFromMessage(msg), AiAction.describePage);
    });

    test('detects improve layout', () {
      const msg = 'Review page "Pump Overview" (key: pump-overview) '
          'and suggest layout improvements or missing assets.';
      expect(detectActionFromMessage(msg), AiAction.improveLayout);
    });

    test('detects duplicate page', () {
      const msg = 'Create a new page similar to "Pump Overview" '
          '(key: pump-overview) but for [describe the target system].';
      expect(detectActionFromMessage(msg), AiAction.duplicatePage);
    });

    test('detects skill chip: create alarm', () {
      const msg = 'Create a new alarm for pump pressure';
      expect(detectActionFromMessage(msg), AiAction.createAlarm);
    });

    test('detects skill chip: create page', () {
      const msg = 'Create a new page for the boiler system';
      expect(detectActionFromMessage(msg), AiAction.createPage);
    });

    test('detects skill chip: show history', () {
      const msg = 'Show the history for pump3.speed';
      expect(detectActionFromMessage(msg), AiAction.showHistory);
    });

    test('detects skill chip: explain asset', () {
      const msg = 'Explain what this asset does: pump3.speed';
      expect(detectActionFromMessage(msg), AiAction.explainAssetChip);
    });

    test('returns freeform for unrecognized messages', () {
      expect(detectActionFromMessage('What is the current temperature?'),
          AiAction.freeform);
      expect(detectActionFromMessage('Hello'), AiAction.freeform);
      expect(detectActionFromMessage('Why is pump 3 running hot?'),
          AiAction.freeform);
    });
  });

  group('filterTools', () {
    test('returns all tools when allowedNames is null', () {
      final tools = ['ping', 'list_tags', 'get_tag_value'];
      final result = filterTools(tools, null, (t) => t);
      expect(result, equals(tools));
    });

    test('filters tools to only those in allowedNames', () {
      final tools = ['ping', 'list_tags', 'get_tag_value', 'create_alarm'];
      final result =
          filterTools(tools, {'list_tags', 'get_tag_value'}, (t) => t);
      expect(result, equals(['list_tags', 'get_tag_value']));
    });

    test('handles allowedNames with unknown tools gracefully', () {
      final tools = ['ping', 'list_tags'];
      final result = filterTools(
        tools,
        {'list_tags', 'nonexistent_tool'},
        (t) => t,
      );
      expect(result, equals(['list_tags']));
    });

    test('returns empty list when no tools match', () {
      final tools = ['ping', 'list_tags'];
      final result =
          filterTools(tools, {'create_alarm', 'update_alarm'}, (t) => t);
      expect(result, isEmpty);
    });

    test('works with custom getName function', () {
      final tools = [
        {'name': 'ping', 'desc': 'health check'},
        {'name': 'list_tags', 'desc': 'browse tags'},
      ];
      final result = filterTools(
        tools,
        {'list_tags'},
        (t) => t['name']!,
      );
      expect(result, hasLength(1));
      expect(result.first['name'], 'list_tags');
    });
  });
}
