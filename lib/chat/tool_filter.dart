/// Maps AI action types to their relevant MCP tool subsets.
///
/// When a user triggers a specific AI action (e.g., right-click "Edit alarm
/// with AI"), only the relevant tools are sent to the LLM. This reduces
/// ambiguity, speeds up tool selection, and prevents unnecessary discovery
/// calls. Freeform chat retains access to all tools.
///
/// Each [AiAction] maps to a [Set<String>] of tool names via [toolsFor].
/// Unknown tool names in the filter are silently ignored (graceful handling
/// when a tool is disabled via McpToolToggles).
library;

/// Identifies the type of AI action the user triggered.
///
/// Used to select which MCP tools the LLM should have access to.
enum AiAction {
  /// Right-click asset in page view: "Debug this asset"
  /// Diagnostic investigation -- read-only runtime tools.
  debugAsset,

  /// Right-click asset in page editor: "Configure with AI"
  /// Suggests key mappings, alarm thresholds, display settings.
  configureAsset,

  /// Right-click asset in page editor: "Explain asset type"
  /// Read-only explanation of what the asset type does.
  explainAsset,

  /// Alarm editor: "Create alarm with AI"
  /// Also used by skill chip "Create alarm".
  createAlarm,

  /// Alarm editor: "Duplicate alarm with AI"
  /// Creates a new alarm based on an existing one.
  duplicateAlarm,

  /// Alarm editor: "Edit alarm with AI"
  /// Updates an existing alarm configuration.
  editAlarm,

  /// Page editor: "Describe this page"
  /// Read-only description of page contents.
  describePage,

  /// Page editor: "Improve layout"
  /// Reviews page layout and suggests changes.
  improveLayout,

  /// Page editor: "Duplicate with AI"
  /// Creates a new page similar to an existing one.
  duplicatePage,

  /// Skill chip: "Create page"
  createPage,

  /// Skill chip: "Show history"
  /// Queries alarm history and trend data.
  showHistory,

  /// Skill chip: "Explain asset"
  /// Same tools as [explainAsset] but triggered from chat chip.
  explainAssetChip,

  /// Freeform chat -- no specific action.
  /// All tools are available (no filtering).
  freeform,
}

/// Returns the set of tool names relevant to [action].
///
/// Returns `null` for [AiAction.freeform], indicating no filtering
/// (all tools should be sent to the LLM).
///
/// Each tool is included with a comment explaining WHY it is needed
/// for that action. Tool names that are not registered on the MCP server
/// (e.g., because the toggle is off) are silently ignored at the call site.
Set<String>? toolsFor(AiAction action) {
  switch (action) {
    case AiAction.debugAsset:
      // Diagnostic investigation of a specific asset.
      // Asset config is already in context -- only need runtime data.
      // Tech docs and PLC code are now included statically in the prompt.
      // NOTE: When all context is pre-computed (_isDebugContextComplete),
      // chat.dart overrides this to only {get_plc_code_block}. This
      // partial set is the fallback for when some context is missing.
      return const {
        'get_tag_value', // live value of the asset's key
        'list_tags', // discover related tags if key name is partial
        'query_alarm_history', // recent alarm activations for this asset
        'list_alarms', // check if asset currently has active alarms
        'query_trend_data', // historical trend data for analysis
        'get_plc_code_block', // fetch full source for blocks in call graph
      };

    case AiAction.configureAsset:
      // Help configure an asset -- needs tags, key mappings, and write tools.
      // Asset config is already in context.
      return const {
        'list_tags', // discover tags matching this asset
        'get_tag_value', // check current value of candidate tags
        'list_key_mappings', // see existing key mappings
        'create_key_mapping', // propose new key mapping
        'update_key_mapping', // propose key mapping changes
        'list_alarm_definitions', // see existing alarms for context
        'create_alarm', // propose alarm thresholds
        'search_tech_docs', // find specs for thresholds
        'get_tech_doc_section', // read spec content
        'list_asset_types', // understand asset capabilities
      };

    case AiAction.explainAsset:
    case AiAction.explainAssetChip:
      // Read-only explanation of asset type and its purpose.
      // Asset config is already in context (for explainAsset).
      return const {
        'list_asset_types', // catalog of asset types and properties
        'get_tag_value', // show current value for context
        'search_tech_docs', // find documentation about this asset type
        'get_tech_doc_section', // read relevant documentation
        'search_plc_code', // understand PLC logic behind this asset
        'get_plc_code_block', // read full PLC code block
        'search_drawings', // find wiring diagrams
        'list_key_mappings', // explain what keys are connected
      };

    case AiAction.createAlarm:
      // Create a brand new alarm from scratch.
      return const {
        'create_alarm', // the primary action: create alarm proposal
        'list_tags', // discover available tags for expression
        'get_tag_value', // check current values for threshold setting
        'list_alarm_definitions', // avoid duplicating existing alarms
        'list_key_mappings', // understand key-to-node mappings
        'search_tech_docs', // find specs for alarm thresholds
        'get_tech_doc_section', // read spec content
      };

    case AiAction.duplicateAlarm:
      // Create a new alarm based on an existing one.
      // Alarm config is already in context.
      return const {
        'create_alarm', // primary action: create new alarm proposal
        'list_tags', // discover tags for modified expression
        'get_tag_value', // check current values for threshold
        'search_tech_docs', // find specs if changing thresholds
        'get_tech_doc_section', // read spec content
      };

    case AiAction.editAlarm:
      // Modify an existing alarm.
      // Alarm config is already in context.
      return const {
        'update_alarm', // primary action: update alarm proposal
        'get_tag_value', // check current values for threshold
        'list_tags', // discover tags if changing expression
        'search_tech_docs', // find specs for new thresholds
        'get_tech_doc_section', // read spec content
        'search_plc_code', // understand PLC logic if relevant
        'get_plc_code_block', // read full PLC code
      };

    case AiAction.describePage:
      // Read-only description of page contents.
      return const {
        'get_asset_detail', // get full page config to describe
        'list_assets', // list assets on the page
        'list_key_mappings', // understand what data points are shown
        'get_tag_value', // show current values of page assets
        'list_tags', // discover related tags
      };

    case AiAction.improveLayout:
      // Review page and suggest improvements.
      return const {
        'get_asset_detail', // get current page layout
        'list_assets', // see all available assets
        'list_asset_types', // know what widget types are available
        'list_key_mappings', // understand data point connections
        'list_tags', // discover additional tags to display
        'propose_page', // propose page layout changes
        'search_tech_docs', // find best practices
        'get_tech_doc_section', // read documentation
      };

    case AiAction.duplicatePage:
    case AiAction.createPage:
      // Create a new page layout.
      return const {
        'propose_page', // primary action: create page proposal
        'list_asset_types', // know what widgets are available
        'list_assets', // see existing pages for reference
        'get_asset_detail', // reference existing page layouts
        'list_tags', // discover tags for key bindings
        'list_key_mappings', // understand key-to-node mappings
        'get_tag_value', // verify tags exist and have values
      };

    case AiAction.showHistory:
      // Show history for an asset or alarm.
      return const {
        'query_alarm_history', // primary: alarm history records
        'query_trend_data', // primary: trend data over time
        'list_alarms', // list active alarms for context
        'get_alarm_detail', // get alarm details for history context
        'get_tag_value', // show current value alongside history
        'list_tags', // discover tags for trend queries
      };

    case AiAction.freeform:
      // No filtering -- all tools available.
      return null;
  }
}

/// Detects the [AiAction] from message content by looking for known patterns.
///
/// This is a heuristic approach used when the action type is not explicitly
/// provided (e.g., when the message comes through [chatPrefillProvider] or
/// [AiContextAction.openChatAndSend]). The detection checks for marker text
/// that is present in the prefill templates defined in [asset_context_menu.dart],
/// [alarm.dart], [page_editor.dart], and [chat_skill_chips.dart].
///
/// Returns [AiAction.freeform] if no pattern matches.
AiAction detectActionFromMessage(String message) {
  // Debug asset -- sent immediately via openChatAndSend
  if (message.startsWith('Debug asset:') &&
      message.contains('[ASSET CONTEXT')) {
    return AiAction.debugAsset;
  }

  // Alarm editor actions -- prefilled prompts reference specific tools
  if (message.contains('update_alarm tool')) {
    return AiAction.editAlarm;
  }
  if (message.contains('create_alarm tool') &&
      message.contains('[ALARM CONTEXT')) {
    return AiAction.duplicateAlarm;
  }
  if (message.contains('create_alarm tool')) {
    return AiAction.createAlarm;
  }

  // Asset context menu actions -- prefilled prompts from buildXxxMessage()
  if (message.startsWith('Help me configure asset') &&
      message.contains('[ASSET CONTEXT')) {
    return AiAction.configureAsset;
  }
  if (message.startsWith('Explain the') &&
      message.contains('[ASSET CONTEXT')) {
    return AiAction.explainAsset;
  }

  // Page editor actions -- prefilled prompts with page key
  if (message.startsWith('Describe page')) {
    return AiAction.describePage;
  }
  if (message.startsWith('Review page') &&
      message.contains('suggest layout improvements')) {
    return AiAction.improveLayout;
  }
  if (message.startsWith('Create a new page similar to')) {
    return AiAction.duplicatePage;
  }

  // Skill chip actions -- partial prompts the user will extend
  if (message.startsWith('Create a new alarm for')) {
    return AiAction.createAlarm;
  }
  if (message.startsWith('Create a new page for')) {
    return AiAction.createPage;
  }
  if (message.startsWith('Show the history for')) {
    return AiAction.showHistory;
  }
  if (message.startsWith('Explain what this asset does:')) {
    return AiAction.explainAssetChip;
  }

  return AiAction.freeform;
}

/// Filters a list of tools to only include those in [allowedNames].
///
/// If [allowedNames] is null, returns all tools (no filtering).
/// Tools whose names are not in [allowedNames] are silently dropped.
/// This handles the case where [allowedNames] contains a tool name
/// that is not registered (e.g., because its toggle is disabled).
List<T> filterTools<T>(
  List<T> tools,
  Set<String>? allowedNames,
  String Function(T tool) getName,
) {
  if (allowedNames == null) return tools;
  return tools.where((t) => allowedNames.contains(getName(t))).toList();
}
