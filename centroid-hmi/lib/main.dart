import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beamer/beamer.dart';
import 'package:dbus/dbus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:amplify_secure_storage_dart/amplify_secure_storage_dart.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:upgrader/upgrader.dart';
import 'package:centroidx_upgrader/centroidx_upgrader.dart';

import 'package:tfc/route_registry.dart';
import 'package:tfc/routes.dart';
import 'package:tfc/models/menu_item.dart';
import 'package:tfc/pages/page_view.dart';
import 'package:tfc/pages/page_editor.dart';
import 'package:tfc/pages/not_found.dart';
import 'package:tfc/pages/preferences.dart';
import 'package:tfc/pages/alarm_editor.dart';
import 'package:tfc/pages/alarm_view.dart';
import 'package:tfc/pages/ip_settings.dart';
import 'package:tfc/pages/dbus_login.dart';
import 'package:tfc/pages/history_view.dart';
import 'package:tfc/pages/server_config.dart';
import 'package:tfc/pages/key_repository.dart';
import 'package:tfc/pages/about_linux.dart';
import 'package:tfc/pages/tech_doc_library.dart';
import 'package:tfc/transition_delegate.dart';
import 'package:tfc/providers/theme.dart';
import 'package:tfc/core/preferences.dart';
import 'package:tfc/page_creator/page.dart';

import 'package:tfc/theme.dart';
import 'package:tfc/page_creator/assets/registry.dart';
import 'package:tfc/widgets/base_scaffold.dart';
import 'package:tfc/widgets/nav_dropdown.dart';
import 'package:mcp_dart/mcp_dart.dart' show ElicitResult;
import 'package:tfc/chat/chat_overlay.dart';
import 'package:tfc/chat/elicitation_dialog.dart';
import 'package:tfc/drawings/drawing_overlay.dart';
import 'package:tfc/providers/chat.dart';
import 'package:tfc/providers/mcp_bridge.dart';
import 'package:tfc/providers/navigator_key.dart';
import 'package:tfc/providers/proposal_watcher.dart';
import 'package:tfc/providers/proposal_state.dart';
import 'package:tfc/providers/scaffold_messenger_key.dart';

import 'package:tfc_dart/core/secure_storage/secure_storage.dart';
import 'package:tfc_dart/core/log_config.dart';
import 'package:tfc/core/secure_storage/other.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:tfc/widgets/proposal_banner.dart';
import 'package:tfc/marionette/route_logger.dart';

import 'marionette_init.dart';
import 'pages/version_manager_page.dart';

/// Enable with: --dart-define=MARIONETTE=true
const _enableMarionette = bool.fromEnvironment('MARIONETTE');

/// Synchronous log file handle for MSIX debug logging.
///
/// In MSIX, neither Flutter's print() nor dart:io's stdout route through the
/// C++ freopen_s redirect. We open the log file directly from Dart using
/// synchronous IO (RandomAccessFile) to guarantee writes are flushed.
RandomAccessFile? _logFile;

void _debugPrint(Zone self, ZoneDelegate parent, Zone zone, String line) {
  if (_logFile != null) {
    _logFile!.writeStringSync('$line\n');
  }
  // Forward to parent so debugger/DevTools still works.
  parent.print(zone, line);
}

void main() {
  // Ignore SIGPIPE so broken-pipe writes become IOExceptions instead of
  // killing the process.  The MCP HTTP server, OPC UA client, and pdfium
  // background isolate all perform native socket/pipe IO that can trigger
  // SIGPIPE when the remote end closes unexpectedly.
  if (Platform.isLinux || Platform.isMacOS) {
    try {
      ProcessSignal.sigpipe.watch().listen((_) {
        stderr.writeln('SIGPIPE received — broken pipe (ignored)');
      });
    } on SignalException {
      // flutter-elinux does not support signal watching
    }
  }

  final logFilePath = Platform.environment['CENTROID_LOG_FILE'];
  final debugMode = Platform.environment['CENTROID_STDOUT'] == '1' ||
      Platform.environment['CENTROID_STDOUT'] == 'true' ||
      logFilePath != null;

  if (debugMode && logFilePath != null) {
    try {
      _logFile = File(logFilePath).openSync(mode: FileMode.append);
    } catch (_) {}
  }

  initLogConfig();

  if (_enableMarionette) {
    initMarionette();
    _startApp(debugMode);
  } else {
    runZonedGuarded(() {
      WidgetsFlutterBinding.ensureInitialized();
      _startApp(debugMode);
    }, (error, stackTrace) {
      stderr.writeln('Unhandled async error: $error');
      stderr.writeln('$stackTrace');
    },
    zoneSpecification: debugMode
        ? ZoneSpecification(print: _debugPrint)
        : null,
    );
  }
}

/// All initialisation that depends on a Flutter binding being present,
/// through to [runApp].  Called from the same zone that initialised the
/// binding so that Flutter's zone-check in [runApp] is satisfied.
Future<void> _startApp([bool debugMode = false]) async {
  if (debugMode) {
    print('[CentroidX] v${Platform.version} starting...');
    print('[CentroidX] Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    print('[CentroidX] Executable: ${Platform.resolvedExecutable}');
    print('[CentroidX] Environment: CENTROID_STDOUT=${Platform.environment['CENTROID_STDOUT'] ?? 'unset'}, '
        'CENTROID_LOG_FILE=${Platform.environment['CENTROID_LOG_FILE'] ?? 'unset'}, '
        'CENTROID_LOG_LEVEL=${Platform.environment['CENTROID_LOG_LEVEL'] ?? 'unset'}, '
        'CENTROID_OPCUA_LOG_LEVEL=${Platform.environment['CENTROID_OPCUA_LOG_LEVEL'] ?? 'unset'}');
  }

  pdfrxFlutterInitialize();
  AmplifySecureStorageDart.registerWith();
  if (Platform.isWindows) {
    SecureStorage.setInstance(OtherSecureStorage());
  }

  // Register your custom asset type
  // AssetRegistry.registerFromJsonFactory<ChecklistsConfig>(ChecklistsConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<ChecklistsConfig>(ChecklistsConfig.preview);

  // AssetRegistry.registerFromJsonFactory<SpeedBatcherConfig>(SpeedBatcherConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<SpeedBatcherConfig>(SpeedBatcherConfig.preview);

  // AssetRegistry.registerFromJsonFactory<AirCabConfig>(AirCabConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<AirCabConfig>(AirCabConfig.preview);

  // AssetRegistry.registerFromJsonFactory<ElCabConfig>(ElCabConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<ElCabConfig>(ElCabConfig.preview);

  // AssetRegistry.registerFromJsonFactory<RecipesConfig>(RecipesConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<RecipesConfig>(RecipesConfig.preview);

  // AssetRegistry.registerFromJsonFactory<GateStatusConfig>(GateStatusConfig.fromJson);
  // AssetRegistry.registerDefaultFactory<GateStatusConfig>(GateStatusConfig.preview);

  final registry = RouteRegistry();

  final environmentVariableIsGod = Platform.environment['TFC_GOD'] == 'true';

  registry.addMenuItem(const MenuItem(label: 'Home', path: '/', icon: Icons.home));

  registry.addMenuItem(const MenuItem(label: 'Alarm View', path: '/alarm-view', icon: Icons.alarm));

  // This is not ideal, if a second HMI adds a page, we will need to restart the app twice
  final prefs = SharedPreferencesWrapper(SharedPreferencesAsync());
  final pageManager = PageManager(pages: {}, prefs: prefs);
  await pageManager.load();

  final extraMenuItems = pageManager.getRootMenuItems();

  for (final menuItem in extraMenuItems) {
    registry.addMenuItem(menuItem);
  }

  registry.addMenuItem(
    MenuItem(
      label: 'Advanced',
      path: '/advanced',
      icon: Icons.settings,
      children: [
        if (Platform.isLinux)
          MenuItem(label: 'IP Settings', path: '/advanced/ip-settings', icon: Icons.settings_ethernet),
        if (Platform.isLinux) MenuItem(label: 'About Linux', path: '/advanced/about-linux', icon: Icons.info),
        if (environmentVariableIsGod) MenuItem(label: 'Page Editor', path: '/advanced/page-editor', icon: Icons.edit),
        if (environmentVariableIsGod)
          MenuItem(label: 'Preferences', path: '/advanced/preferences', icon: Icons.settings),
        if (environmentVariableIsGod)
          MenuItem(label: 'Alarm Editor', path: '/advanced/alarm-editor', icon: Icons.alarm),
        MenuItem(label: 'History View', path: '/advanced/history-view', icon: Icons.history),
        MenuItem(label: 'Server Config', path: '/advanced/server-config', icon: FontAwesomeIcons.server),
        MenuItem(label: 'Key Repository', path: '/advanced/key-repository', icon: FontAwesomeIcons.key),
        MenuItem(label: 'Version Manager', path: '/advanced/version-manager', icon: Icons.update),
        MenuItem(label: 'Knowledge Base', path: '/advanced/knowledge-base', icon: Icons.library_books),
      ],
    ),
  );

  final locationBuilder = createLocationBuilder(extraMenuItems);

  final upgrader = Upgrader(
    storeController: UpgraderStoreController(
      onWindows: () => GitHubReleaseStore(owner: 'centroid-is', repo: 'tfc-hmi'),
      onLinux: () => GitHubReleaseStore(owner: 'centroid-is', repo: 'tfc-hmi'),
      onMacOS: () => GitHubReleaseStore(owner: 'centroid-is', repo: 'tfc-hmi'),
    ),
    debugLogging: true,
  );

  runApp(ProviderScope(
    child: UpgradeAlert(
      upgrader: upgrader,
      onUpdate: () {
        final targetVersion =
            upgrader.state.versionInfo?.appStoreVersion?.toString() ?? '';
        unawaited(
          managerLauncher
              .launchForUpdate(
                version: targetVersion,
                flutterPid: pid,
              )
              .then((_) => exit(0)),
        );
        return false;
      },
      child: MyApp(locationBuilder: locationBuilder),
    ),
  ));
}

Completer<DBusClient> dbusCompleter = Completer();

final managerLauncher = ManagerLauncher(
  assetLoader: (key) async {
    final bd = await rootBundle.load(key);
    return bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
  },
);

RoutesLocationBuilder createLocationBuilder(List<MenuItem> extraMenuItems) {
  final routes = {
    // '/': (context, state, args) => BeamPage(
    //       // this will be replaced most likely
    //       key: const ValueKey('/'),
    //       title: 'Home',
    //       child: Consumer(
    //         builder: (context, ref, _) {
    //           return AssetView(
    //             pageName: 'Home',
    //           );
    //         },
    //       ),
    //     ),
    '/advanced/ip-settings': (context, state, args) => BeamPage(
          key: const ValueKey('/advanced/ip-settings'),
          title: 'IP Settings',
          child: Consumer(
            builder: (context, ref, _) {
              // I dont like this but lets continue
              return FutureBuilder<DBusClient>(
                future: dbusCompleter.future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return BaseScaffold(
                      title: 'IP Settings',
                      body: Center(
                        child: LoginForm(
                          onLoginSuccess: (newDbusClient) async {
                            logger.i('Login successful');
                            await Future.delayed(const Duration(milliseconds: 100));
                            if (!dbusCompleter.isCompleted) {
                              dbusCompleter.complete(newDbusClient);
                            }
                          },
                        ),
                      ),
                    );
                  }
                  return IpSettingsPage(dbusClient: snapshot.data!);
                },
              );
            },
          ),
        ),
    '/advanced/about-linux': (context, state, args) => BeamPage(
          key: const ValueKey('/advanced/about-linux'),
          title: 'About Linux',
          child: Consumer(
            builder: (context, ref, _) {
              // I dont like this but lets continue
              return FutureBuilder<DBusClient>(
                future: dbusCompleter.future,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return BaseScaffold(
                      title: 'About Linux',
                      body: Center(
                        child: LoginForm(
                          onLoginSuccess: (newDbusClient) async {
                            logger.i('Login successful');
                            await Future.delayed(const Duration(milliseconds: 100));
                            if (!dbusCompleter.isCompleted) {
                              dbusCompleter.complete(newDbusClient);
                            }
                          },
                        ),
                      ),
                    );
                  }
                  return AboutLinuxPage(dbusClient: snapshot.data!);
                },
              );
            },
          ),
        ),
    '/advanced/page-editor': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/page-editor'), title: 'Page Editor',
                 child: PageEditor(proposalData: args is String ? args : null)),
    '/advanced/preferences': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/preferences'), title: 'Preferences', child: PreferencesPage()),
    '/advanced/alarm-editor': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/alarm-editor'), title: 'Alarm Editor',
                 child: AlarmEditorPage(proposalData: args is String ? args : null)),
    '/advanced/history-view': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/history-view'), title: 'History View', child: HistoryViewPage()),
    '/advanced/server-config': (context, state, args) =>
        BeamPage(key: const ValueKey('/advanced/server-config'), title: 'Server Config', child: ServerConfigPage()),
    '/advanced/key-repository': (context, state, args) => BeamPage(
        key: const ValueKey('/advanced/key-repository'), title: 'Key Repository',
        child: KeyRepositoryPage(proposalData: args is String ? args : null)),
    '/advanced/version-manager': (context, state, args) => BeamPage(
          key: const ValueKey('/advanced/version-manager'),
          title: 'Version Manager',
          child: VersionManagerPage(launcher: managerLauncher),
        ),
    '/advanced/knowledge-base': (context, state, args) => BeamPage(
        key: const ValueKey('/advanced/knowledge-base'), title: 'Knowledge Base', child: const TechDocLibraryPage()),
    AppRoutes.alarmView: (context, state, args) =>
        BeamPage(key: const ValueKey('/alarm-view'), title: 'Alarm View', child: AlarmViewPage()),
  };

  addRoute(MenuItem menuItem) {
    // Register route for this item if it has a non-empty path
    if (menuItem.path != null && menuItem.path!.isNotEmpty) {
      routes[menuItem.path!] = (context, state, args) => BeamPage(
            key: ValueKey(menuItem.path!),
            title: menuItem.label,
            child: Consumer(
              builder: (context, ref, _) {
                return AssetView(pageName: menuItem.path!);
              },
            ),
          );
    }
    // Recurse into all children
    for (final child in menuItem.children) {
      addRoute(child);
    }
  }

  for (final menuItem in extraMenuItems) {
    addRoute(menuItem);
  }

  return RoutesLocationBuilder(routes: routes);
}

/// Wires the elicitation UI handler into the MCP bridge so that write-tool
/// proposals trigger a confirm/deny dialog instead of auto-accepting.
///
/// The handler uses [navigatorKeyProvider] to obtain a valid [BuildContext]
/// below the app [Navigator], then shows an [ElicitationDialog] and
/// returns the user's response as an [ElicitResult].
void _wireElicitationHandler(WidgetRef ref) {
  final bridge = ref.read(mcpBridgeProvider);
  // Only set once — avoid replacing on every rebuild.
  if (bridge.elicitationHandler != null) return;

  bridge.elicitationHandler = (request) async {
    final navKey = ref.read(navigatorKeyProvider);
    final ctx = navKey?.currentContext;
    if (ctx == null || !ctx.mounted) {
      // No navigator context available — fall back to auto-accept.
      return const ElicitResult(action: 'accept', content: {'confirm': true});
    }
    final completer = Completer<ElicitResult>();
    showElicitationDialog(
      context: ctx,
      request: request,
      completer: completer,
    );
    return completer.future;
  };
}

class MyApp extends ConsumerWidget {
  MyApp({super.key, required RoutesLocationBuilder locationBuilder})
      : routerDelegate = BeamerDelegate(
          notFoundPage: const BeamPage(child: PageNotFound()),
          transitionDelegate: MyNoAnimationTransitionDelegate(),
          locationBuilder: (routeInformation, context) => locationBuilder(routeInformation, context),
        ) {
    // Marionette route logger: emits [ROUTE] /path log entries so agents
    // can verify navigation via getLogs instead of taking screenshots.
    // The const _enableMarionette guard ensures the MarionetteRouteLogger
    // import and this code path are tree-shaken from production builds.
    if (_enableMarionette) {
      MarionetteRouteLogger(routerDelegate);
    }
  }

  final BeamerDelegate routerDelegate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeNotifierProvider);
    final (light, dark) = solarized();

    // Initialize MCP server lifecycle management
    ref.watch(mcpServerLifecycleProvider);

    // Initialize chat lifecycle management (MCP bridge connect/disconnect)
    ref.watch(chatLifecycleProvider);

    // Expose the BeamerDelegate's navigator key so overlay widgets
    // (chat, drawings, FAB) can show dialogs / access Navigator.
    // Defer to avoid modifying provider state during build.
    Future.microtask(() {
      ref.read(navigatorKeyProvider.notifier).state = routerDelegate.navigatorKey;
    });

    // Wire elicitation UI dialog into MCP bridge so write-tool proposals
    // show a confirm/deny dialog instead of auto-accepting.
    _wireElicitationHandler(ref);

    final app = MaterialApp.router(
      title: 'CentroidX',
      scaffoldMessengerKey: globalScaffoldMessengerKey,
      themeMode: themeAsync.when(
        data: (themeMode) => themeMode,
        loading: () => ThemeMode.system,
        error: (_, __) => ThemeMode.system,
      ),
      theme: light,
      darkTheme: dark,
      routerDelegate: routerDelegate,
      routeInformationParser: BeamerParser(),
      builder: (context, navigatorChild) {
        return Consumer(
          builder: (context, ref, _) {
            final drawingVisible = ref.watch(drawingVisibleProvider);
            final chatVisible = ref.watch(chatVisibleProvider);
            // Use select() to only rebuild when the SSE server running
            // state or port changes, NOT on every McpBridgeNotifier
            // notification (tool list updates, connection state
            // transitions, etc.).
            final mcpRunning = ref.watch(mcpBridgeProvider.select(
              (b) => b.isRunning,
            ));
            final mcpPort = ref.watch(mcpBridgeProvider.select(
              (b) => b.currentState.port,
            ));
            final chatEnabled = ref.watch(mcpChatEnabledProvider).valueOrNull ?? false;

            // Feed new MCP proposals into universal state provider.
            // Proposals are surfaced inline in chat via the embedded proposal card.
            ref.listen<ProposalWatcher?>(proposalWatcherProvider, (prev, next) {
              if (next == null) return;
              final stateNotifier = ref.read(proposalStateProvider.notifier);
              for (final p in next.pending) {
                stateNotifier.addProposal(p);
                next.markNotified(p.id);
              }
            });

            return Stack(
              children: [
                navigatorChild!, // existing HMI content
                const ProposalBanner(),
                if (drawingVisible) const DrawingOverlay(),
                if (chatEnabled && chatVisible) const ChatOverlay(),
                // Chat FAB and MCP indicator — hidden when a nav
                // dropdown popup is open so the FAB does not render
                // on top of the menu (the FAB lives above the
                // Navigator's Overlay in the widget tree).
                ValueListenableBuilder<bool>(
                  valueListenable: NavDropdown.isAnyMenuOpen,
                  builder: (context, navMenuOpen, _) {
                    return Stack(
                      children: [
                        // Chat FAB (when chat enabled but overlay closed)
                        if (chatEnabled && !chatVisible && !navMenuOpen)
                          Positioned(
                            bottom: 90,
                            right: 16,
                            child: FloatingActionButton(
                              key: const ValueKey<String>('chat-fab'),
                              onPressed: () => ref.read(chatVisibleProvider.notifier).state = true,
                              // tooltip removed: MaterialApp.builder is above
                              // Navigator's Overlay, so Tooltip crashes with
                              // "No Overlay widget found".
                              tooltip: null,
                              // heroTag disabled: Hero requires a Navigator
                              // ancestor, but this FAB is above the Navigator
                              // in the widget tree (MaterialApp.builder Stack).
                              heroTag: null,
                              child: const Icon(Icons.chat),
                            ),
                          ),
                        // MCP server status indicator (debug only)
                        if (kDebugMode && mcpRunning && !navMenuOpen)
                          Positioned(
                            bottom: chatEnabled && !chatVisible ? 82 : 8,
                            right: chatEnabled && !chatVisible ? 76 : 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.hub, color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'MCP :${mcpPort ?? '?'}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );

    return BeamerProvider(routerDelegate: routerDelegate, child: app);
  }
}
