/// Compile-time feature flags.
///
/// Each flag is a `const` read from a `--dart-define`, so a disabled
/// feature's code is tree-shaken out of the built binary entirely. Defaults
/// are `true` so development builds and the test suite exercise every
/// feature; deployment builds opt out explicitly, e.g.:
///
///     flutter build linux --dart-define=TFC_CHAT=false
library;

/// Whether the in-app AI chat is compiled into the app: the chat overlay
/// and FAB, the LLM providers (Claude/OpenAI/Gemini), the AI context menus,
/// and the in-process MCP client that serves them.
///
/// The MCP SSE server and the proposal review UI are deliberately NOT gated
/// by this flag — external MCP agents and operator proposal approval keep
/// working when chat is off.
const bool kChatEnabled = bool.fromEnvironment('TFC_CHAT', defaultValue: true);
