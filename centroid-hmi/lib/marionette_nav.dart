/// Pre-defined Marionette navigation paths.
///
/// These constants document the exact tap sequences needed to reach common
/// navigation targets, removing the need for `interactiveElements` discovery
/// which is slow and unreliable.
///
/// ## Usage pattern (in Marionette agent shell scripts)
///
/// ```bash
/// # Navigate to Alarm Editor:
/// curl "$BASE/ext.flutter.marionette.tap?isolateId=$ID&key=nav-advanced"
/// sleep 1
/// curl "$BASE/ext.flutter.marionette.tap?isolateId=$ID&text=Alarm%20Editor"
/// sleep 1
/// # Verify via getLogs — look for: [ROUTE] /advanced/alarm-editor
/// curl "$BASE/ext.flutter.marionette.getLogs?isolateId=$ID"
/// ```
///
/// ## Route verification
///
/// Instead of taking a screenshot after navigation, query `getLogs` and look
/// for the `[ROUTE]` prefix. The route logger (enabled with `--dart-define=
/// MARIONETTE=true`) emits log entries like:
///
///     [ROUTE] /advanced/alarm-editor
///     [ROUTE] /advanced/page-editor
///     [ROUTE] /alarm-view
///
/// This is instant compared to the 3+ seconds a screenshot round-trip takes.
library;

/// Semantic keys for interactive widgets.
///
/// [NavDropdown] items get `ValueKey<String>('nav-${label.toLowerCase()}')`.
/// Direct [NavigationDestination] items (Home, Alarm View) do NOT have
/// ValueKeys -- tap them by text label instead.
class NavKeys {
  NavKeys._();

  /// Advanced dropdown (opens popup menu with sub-items).
  /// This is a [NavDropdown] with a [ValueKey].
  static const advanced = 'nav-advanced';

  /// Chat floating action button.
  static const chatFab = 'chat-fab';

  /// Chat overlay close button.
  static const chatClose = 'chat-close-button';

  /// Chat overflow menu button.
  static const chatOverflow = 'chat-overflow-menu';

  /// Chat provider dropdown.
  static const chatProviderDropdown = 'chat-provider-dropdown';

  /// Chat message input field.
  static const chatMessageInput = 'chat-message-input';

  /// Chat send button.
  static const chatSendButton = 'chat-send-button';

  /// Chat API key indicator.
  static const chatApiKeyIndicator = 'chat-api-key-indicator';

  /// Chat API key text field.
  static const chatApiKeyField = 'chat-api-key-field';

  /// Chat base URL text field.
  static const chatBaseUrlField = 'chat-base-url-field';

  /// Chat API key cancel button.
  static const chatApiKeyCancel = 'chat-api-key-cancel';

  /// Chat API key save button.
  static const chatApiKeySave = 'chat-api-key-save';

  /// Drawing overlay close button.
  static const drawingClose = 'drawing-close-button';
}

/// Routes as they appear in `[ROUTE]` log entries.
class NavRoutes {
  NavRoutes._();

  static const home = '/';
  static const alarmView = '/alarm-view';
  static const ipSettings = '/advanced/ip-settings';
  static const aboutLinux = '/advanced/about-linux';
  static const pageEditor = '/advanced/page-editor';
  static const preferences = '/advanced/preferences';
  static const alarmEditor = '/advanced/alarm-editor';
  static const historyView = '/advanced/history-view';
  static const serverConfig = '/advanced/server-config';
  static const keyRepository = '/advanced/key-repository';
  static const knowledgeBase = '/advanced/knowledge-base';
}

/// Pre-defined navigation sequences.
///
/// Each entry is a list of [NavStep]s to execute in order. Between each step
/// the agent should sleep ~1 second.
class NavPaths {
  NavPaths._();

  /// Navigate to Alarm Editor.
  /// Tap: nav-advanced (key) -> "Alarm Editor" (text)
  /// Verify: [ROUTE] /advanced/alarm-editor
  static const alarmEditor = [
    NavStep.tapKey(NavKeys.advanced),
    NavStep.tapText('Alarm Editor'),
  ];

  /// Navigate to Page Editor.
  /// Tap: nav-advanced (key) -> "Page Editor" (text)
  /// Verify: [ROUTE] /advanced/page-editor
  static const pageEditor = [
    NavStep.tapKey(NavKeys.advanced),
    NavStep.tapText('Page Editor'),
  ];

  /// Navigate to Preferences.
  /// Tap: nav-advanced (key) -> "Preferences" (text)
  /// Verify: [ROUTE] /advanced/preferences
  static const preferencesPage = [
    NavStep.tapKey(NavKeys.advanced),
    NavStep.tapText('Preferences'),
  ];

  /// Navigate to History View.
  /// Tap: nav-advanced (key) -> "History View" (text)
  /// Verify: [ROUTE] /advanced/history-view
  static const historyView = [
    NavStep.tapKey(NavKeys.advanced),
    NavStep.tapText('History View'),
  ];

  /// Navigate to Server Config.
  /// Tap: nav-advanced (key) -> "Server Config" (text)
  /// Verify: [ROUTE] /advanced/server-config
  static const serverConfig = [
    NavStep.tapKey(NavKeys.advanced),
    NavStep.tapText('Server Config'),
  ];

  /// Navigate to Key Repository.
  /// Tap: nav-advanced (key) -> "Key Repository" (text)
  /// Verify: [ROUTE] /advanced/key-repository
  static const keyRepository = [
    NavStep.tapKey(NavKeys.advanced),
    NavStep.tapText('Key Repository'),
  ];

  /// Navigate to Knowledge Base (Tech Docs).
  /// Tap: nav-advanced (key) -> "Knowledge Base" (text)
  /// Verify: [ROUTE] /advanced/knowledge-base
  static const knowledgeBase = [
    NavStep.tapKey(NavKeys.advanced),
    NavStep.tapText('Knowledge Base'),
  ];

  /// Navigate to Alarm View.
  /// Single tap: "Alarm View" (text) -- no ValueKey on NavigationDestination.
  /// Verify: [ROUTE] /alarm-view
  static const alarmView = [
    NavStep.tapText('Alarm View'),
  ];

  /// Navigate to Home.
  /// Single tap: "Home" (text) -- no ValueKey on NavigationDestination.
  /// Verify: [ROUTE] /
  static const home = [
    NavStep.tapText('Home'),
  ];

  /// Open Chat overlay.
  /// Single tap: chat-fab (key)
  /// Verify: chat overlay widget appears (use interactiveElements or
  /// check for chat-close-button key)
  static const openChat = [
    NavStep.tapKey(NavKeys.chatFab),
  ];
}

/// A single step in a navigation sequence.
class NavStep {
  /// Tap a widget identified by its [ValueKey<String>].
  const NavStep.tapKey(this.key) : text = null;

  /// Tap a widget identified by its visible text label.
  const NavStep.tapText(this.text) : key = null;

  /// The key to tap (mutually exclusive with [text]).
  final String? key;

  /// The text label to tap (mutually exclusive with [key]).
  final String? text;

  /// Returns the Marionette tap URL query parameter fragment.
  ///
  /// Example: `key=nav-advanced` or `text=Alarm%20Editor`
  String get queryParam {
    if (key != null) return 'key=${Uri.encodeComponent(key!)}';
    return 'text=${Uri.encodeComponent(text!)}';
  }
}
