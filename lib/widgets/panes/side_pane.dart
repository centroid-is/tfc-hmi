import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pane_chrome.dart';
import 'standard_dialog.dart';

/// A non-modal pane docked to the right edge of the screen.
///
/// This is the HMI's replacement for `showDialog` on **complicated** equipment
/// popups — conveyors, elevators/lifts, 3rd party devices. Unlike a dialog it
/// does not put a barrier over the plant view: the page behind keeps running,
/// keeps updating and stays clickable, so an operator can jog a conveyor from
/// the pane while watching the actual belt on the mimic.
///
/// Open one with [showSidePane]; close it with [closeSidePane] (or the pane's
/// own close button / the Escape key). Only one pane is open at a time —
/// opening a second one replaces the first, and re-opening the same [id]
/// toggles it shut, which is what makes tapping a device twice feel right.
///
/// ### Keep it to one screen
///
/// A side pane is deliberately narrower than a dialog. The body should hold
/// no more information than fits without scrolling: the headline numbers as
/// [PaneMetricTile]s, the commands as [PaneAction]s in the pinned footer.
/// Bulk detail — channel grids, trends, fault history — goes behind a
/// [PaneGraphTile] or [PaneExpandTile], which open a free-floating
/// `StandardDialog` the operator can drag next to the plant view.
///
/// ```dart
/// showSidePane(
///   context: context,
///   id: 'conveyor:${config.key}',
///   builder: (context) => StreamBuilder<DynamicValue>(
///     stream: ...,
///     builder: (context, snap) => SidePane(
///       title: 'CN-04',
///       subtitle: 'Infeed conveyor',
///       icon: Icons.conveyor_belt,
///       status: running ? const PaneStatus.running() : const PaneStatus.stopped(),
///       actions: [PaneAction.destructive(label: 'Fault reset', onPressed: reset)],
///       child: Column(children: [...]),
///     ),
///   ),
/// );
/// ```
class SidePane extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;

  /// Live equipment state, rendered as a chip in the header.
  final PaneStatus? status;

  /// Buttons pinned to the bottom of the pane. `Close` is added automatically
  /// and always sits on the right.
  final List<PaneAction> actions;

  /// Extra control in the header, left of the close button.
  final Widget? headerTrailing;

  /// The pane body.
  final Widget child;

  /// Overrides the close behaviour. Defaults to [closeSidePane].
  final VoidCallback? onClose;

  final String closeLabel;

  /// Whether the body scrolls when it does not fit. Leave `true` — the
  /// intent is that content fits, this is the safety net for small screens.
  final bool scrollable;

  const SidePane({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.status,
    this.actions = const [],
    this.headerTrailing,
    this.onClose,
    this.closeLabel = 'Close',
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final close = onClose ?? closeSidePane;
    final body = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: child,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: title,
          subtitle: subtitle,
          icon: icon,
          status: status,
          onClose: close,
          trailing: headerTrailing,
        ),
        Expanded(
          child: scrollable
              ? SingleChildScrollView(
                  primary: false,
                  child: body,
                )
              : body,
        ),
        PaneActionBar(
          actions: actions,
          onClose: close,
          closeLabel: closeLabel,
        ),
      ],
    );
  }
}

/// Closes [paneId] when its subtree leaves the tree.
///
/// A docked pane lives in the root overlay, so nothing tears it down when the
/// page that opened it goes away. Assets with their own `State` close their
/// pane from `dispose()`; wrap this around a stateless asset body to get the
/// same guarantee without turning it into a `StatefulWidget`.
class SidePaneOwner extends StatefulWidget {
  final String paneId;
  final Widget child;

  const SidePaneOwner({
    super.key,
    required this.paneId,
    required this.child,
  });

  @override
  State<SidePaneOwner> createState() => _SidePaneOwnerState();
}

class _SidePaneOwnerState extends State<SidePaneOwner> {
  @override
  void dispose() {
    closeSidePane(id: widget.paneId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Tunables shared by every docked pane. An app can set these once at
/// start-up instead of passing them at each call site.
abstract final class SidePaneDefaults {
  /// Space kept clear of the app chrome so the pane never covers the
  /// `BaseScaffold` AppBar (top) or NavigationBar (bottom) — an operator must
  /// still see alarms and be able to navigate while a pane is open.
  static EdgeInsets insets = const EdgeInsets.only(
    top: kToolbarHeight,
    bottom: 80,
  );

  /// Gap between the pane and the screen/chrome edges.
  static double margin = 12;

  /// Width used the first time a pane is opened. Afterwards the operator's
  /// last resized width is reused for the rest of the session.
  static double width = 380;

  /// Resize limits. The maximum is also capped at 60% of the window.
  static double minWidth = 300;
  static double maxWidth = 640;
}

/// Opens [builder]'s pane docked to the right edge.
///
/// [id] identifies the equipment (e.g. `'conveyor:CN04'`). Calling
/// `showSidePane` again with the id that is already open closes it, so a
/// single tap handler can serve as an open/close toggle.
///
/// Returns `true` if a pane is showing after the call, `false` if the call
/// toggled it shut.
bool showSidePane({
  required BuildContext context,
  required String id,
  required WidgetBuilder builder,
  double? width,
  EdgeInsets? insets,
  VoidCallback? onClosed,
}) {
  if (SidePaneHost.openId == id) {
    closeSidePane();
    return false;
  }
  SidePaneHost._show(
    context: context,
    id: id,
    builder: builder,
    width: width,
    insets: insets,
    onClosed: onClosed,
  );
  return true;
}

/// Closes the docked pane.
///
/// When [id] is given the pane closes only if that id is the one showing —
/// use this from an asset's `dispose()` so a pane cannot outlive the widget
/// that opened it after a page change.
void closeSidePane({String? id}) => SidePaneHost.close(id: id);

/// Whether a pane (optionally a specific [id]) is currently open.
bool isSidePaneOpen({String? id}) =>
    SidePaneHost.openId != null && (id == null || SidePaneHost.openId == id);

/// Owns the single docked-pane [OverlayEntry].
///
/// Public only so tests can assert on [openId]; call [showSidePane] /
/// [closeSidePane] from application code.
abstract final class SidePaneHost {
  static OverlayEntry? _entry;
  static GlobalKey<_SidePaneShellState>? _shellKey;
  static String? _openId;
  static VoidCallback? _onClosed;

  /// The id of the pane currently showing, or null.
  static String? get openId => _openId;

  /// Width carried over between opens within a session.
  static double _width = SidePaneDefaults.width;

  static void _show({
    required BuildContext context,
    required String id,
    required WidgetBuilder builder,
    double? width,
    EdgeInsets? insets,
    VoidCallback? onClosed,
  }) {
    // Replacing an open pane: drop the old one without its exit animation so
    // the two never overlap.
    _removeNow();

    final overlay = Overlay.of(context, rootOverlay: true);
    if (width != null) _width = width;
    final key = GlobalKey<_SidePaneShellState>();
    _shellKey = key;
    _openId = id;
    _onClosed = onClosed;
    _entry = OverlayEntry(
      builder: (context) => _SidePaneShell(
        key: key,
        insets: insets ?? SidePaneDefaults.insets,
        builder: builder,
      ),
    );
    overlay.insert(_entry!);
  }

  static void close({String? id}) {
    if (_openId == null) return;
    if (id != null && id != _openId) return;
    final shell = _shellKey?.currentState;
    if (shell == null) {
      _removeNow();
      return;
    }
    // Mark closed straight away so a tap during the exit animation opens a
    // fresh pane instead of toggling against a pane that is on its way out.
    _openId = null;
    shell.dismiss().then((_) => _removeNow());
  }

  static void _removeNow() {
    _entry?.remove();
    _entry = null;
    _shellKey = null;
    _openId = null;
    final onClosed = _onClosed;
    _onClosed = null;
    onClosed?.call();
  }

  /// Drops the bookkeeping for a shell that went away on its own — the whole
  /// overlay was torn down by a route change, a hot restart or a test's next
  /// `pumpWidget`. Without this the host would still believe a pane is open
  /// and refuse to show the next one.
  static void _forget(Key? shellKey) {
    if (_shellKey != shellKey) return;
    _entry = null;
    _shellKey = null;
    _openId = null;
    final onClosed = _onClosed;
    _onClosed = null;
    onClosed?.call();
  }
}

/// Geometry, animation, resizing and Escape handling for the docked pane.
class _SidePaneShell extends StatefulWidget {
  final EdgeInsets insets;
  final WidgetBuilder builder;

  const _SidePaneShell({
    super.key,
    required this.insets,
    required this.builder,
  });

  @override
  State<_SidePaneShell> createState() => _SidePaneShellState();
}

class _SidePaneShellState extends State<_SidePaneShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Width of the resize grip along the pane's left edge.
  static const double _gripWidth = 8;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // Escape closes the pane wherever focus happens to be. A non-modal pane
    // never owns focus, so a focus-scoped shortcut would not fire.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    SidePaneHost._forget(widget.key);
    _controller.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    // A floating dialog opened from this pane sits on top of it, so it gets
    // the Escape first and the pane only closes once they are all gone.
    if (!FloatingDialogs.isEmpty) return false;
    closeSidePane();
    return true;
  }

  /// Runs the exit animation. The host removes the overlay entry afterwards.
  Future<void> dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
  }

  void _resize(double dx, double screenWidth) {
    final maxWidth = [
      SidePaneDefaults.maxWidth,
      screenWidth * 0.6,
    ].reduce((a, b) => a < b ? a : b);
    setState(() {
      SidePaneHost._width = (SidePaneHost._width - dx).clamp(
        SidePaneDefaults.minWidth,
        maxWidth < SidePaneDefaults.minWidth
            ? SidePaneDefaults.minWidth
            : maxWidth,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final margin = SidePaneDefaults.margin;
    // Never let the reserved chrome squeeze the pane off a short screen.
    final chrome = widget.insets;
    final maxChrome = screen.height - 160;
    final scale = (chrome.top + chrome.bottom) > maxChrome && maxChrome > 0
        ? maxChrome / (chrome.top + chrome.bottom)
        : 1.0;
    final top = chrome.top * scale + margin;
    final bottom = chrome.bottom * scale + margin;
    final width = SidePaneHost._width.clamp(
      SidePaneDefaults.minWidth,
      screen.width - margin * 2 < SidePaneDefaults.minWidth
          ? SidePaneDefaults.minWidth
          : screen.width - margin * 2,
    );

    return Positioned(
      right: margin,
      top: top,
      bottom: bottom,
      width: width,
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, child) => Transform.translate(
          offset: Offset((1 - _slide.value) * (width + margin), 0),
          child: Opacity(opacity: _slide.value.clamp(0.0, 1.0), child: child),
        ),
        child: Material(
          // Low elevation plus an outline: on the dark solarized theme a
          // heavy shadow reads as a thick black frame around the pane.
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
          color: Theme.of(context).colorScheme.surface,
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: widget.builder(context)),
              // Left-edge grip: drag to widen/narrow. The width persists for
              // the rest of the session so an operator sets it once.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _gripWidth,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (d) =>
                        _resize(d.delta.dx, screen.width),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
