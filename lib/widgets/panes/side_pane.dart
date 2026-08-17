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

  /// Pane width. An app can widen this once at start-up; a caller can
  /// override it per pane via `showSidePane(width: ...)`.
  static double width = 380;

  /// Floor for the width when the window is too narrow to honour it.
  static double minWidth = 300;
}

/// Opens [builder]'s pane docked to the right edge.
///
/// [id] identifies the equipment (e.g. `'conveyor:CN04'`). Calling
/// `showSidePane` again with the id that is already open closes it, so a
/// single tap handler can serve as an open/close toggle.
///
/// Returns `true` if a pane is showing after the call, `false` if the call
/// toggled it shut.
///
/// [resizable] adds a drag handle to the pane's left edge. Equipment panes
/// leave it off — they are a fixed strip and their content is built to fit.
/// Turn it on where the content is not: the page editor's asset config forms
/// range from a colour swatch to a two-column subdevice manager, and no single
/// width suits both. [onWidthChanged] reports each new width so the caller can
/// hand the same one back the next time it opens the pane.
bool showSidePane({
  required BuildContext context,
  required String id,
  required WidgetBuilder builder,
  double? width,
  EdgeInsets? insets,
  VoidCallback? onClosed,
  bool resizable = false,
  ValueChanged<double>? onWidthChanged,
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
    resizable: resizable,
    onWidthChanged: onWidthChanged,
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

  /// Width of the pane currently showing. Set per open, so a wide pane (the
  /// page editor's asset config) does not leave every equipment pane opened
  /// afterwards stretched to its width.
  static double _width = SidePaneDefaults.width;

  static void _show({
    required BuildContext context,
    required String id,
    required WidgetBuilder builder,
    double? width,
    EdgeInsets? insets,
    VoidCallback? onClosed,
    bool resizable = false,
    ValueChanged<double>? onWidthChanged,
  }) {
    // Replacing an open pane: drop the old one without its exit animation so
    // the two never overlap.
    _removeNow();

    final overlay = Overlay.of(context, rootOverlay: true);
    _width = width ?? SidePaneDefaults.width;
    final key = GlobalKey<_SidePaneShellState>();
    _shellKey = key;
    _openId = id;
    _onClosed = onClosed;
    _entry = OverlayEntry(
      builder: (context) => _SidePaneShell(
        key: key,
        insets: insets ?? SidePaneDefaults.insets,
        builder: builder,
        resizable: resizable,
        onWidthChanged: onWidthChanged,
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
  final bool resizable;
  final ValueChanged<double>? onWidthChanged;

  const _SidePaneShell({
    super.key,
    required this.insets,
    required this.builder,
    this.resizable = false,
    this.onWidthChanged,
  });

  @override
  State<_SidePaneShell> createState() => _SidePaneShellState();
}

class _SidePaneShellState extends State<_SidePaneShell>
    with SingleTickerProviderStateMixin {
  /// The pane's own Navigator. The pane lives in the root overlay, and
  /// `Overlay.rearrange` keeps it above every route the app Navigator will
  /// ever push — so a `DropdownButton` menu or `showDialog` opened from pane
  /// content would land BEHIND the pane, invisible but armed (tapping the
  /// dropdown a second time trips the framework's `_dropdownRoute == null`
  /// assertion). Giving the pane subtree its own Navigator makes those routes
  /// open in the pane's overlay instead, on top of the pane.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  late final OverlayEntry _paneEntry = OverlayEntry(builder: _buildPane);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

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
    // Same for anything pushed onto the pane's own Navigator — an open
    // dropdown menu or a modal dialog goes first, the pane after.
    final navigator = _navigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return true;
    }
    closeSidePane();
    return true;
  }

  /// Runs the exit animation. The host removes the overlay entry afterwards.
  Future<void> dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    // Full-screen, but hit-transparent everywhere the pane is not: the
    // Navigator's Overlay claims a tap only where a child does, so the plant
    // view behind stays interactive — the pane remains non-modal.
    return Navigator(
      key: _navigatorKey,
      onGenerateRoute: (_) => null,
      onGenerateInitialRoutes: (_, __) => [_PaneCanvasRoute(_paneEntry)],
    );
  }

  Widget _buildPane(BuildContext context) {
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
    final maxWidth = screen.width - margin * 2 < SidePaneDefaults.minWidth
        ? SidePaneDefaults.minWidth
        : screen.width - margin * 2;
    final width = SidePaneHost._width.clamp(SidePaneDefaults.minWidth, maxWidth);

    // No shadow at all: on the dark solarized theme even a small elevation
    // renders as a black halo, which reads like a warning frame around the
    // pane rather than depth. A hairline outline is enough to separate it
    // from the plant view.
    Widget pane = Material(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      child: widget.builder(context),
    );

    if (widget.resizable) {
      pane = Stack(
        children: [
          Positioned.fill(child: pane),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 10,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Dragging the handle left widens the pane: it is pinned to
                // the right edge, so the left edge is the only one that moves.
                onHorizontalDragUpdate: (details) => _resizeBy(
                  -details.delta.dx,
                  SidePaneDefaults.minWidth,
                  maxWidth,
                ),
              ),
            ),
          ),
        ],
      );
    }

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
        child: pane,
      ),
    );
  }

  void _resizeBy(double delta, double minWidth, double maxWidth) {
    final next = (SidePaneHost._width + delta).clamp(minWidth, maxWidth);
    if (next == SidePaneHost._width) return;
    SidePaneHost._width = next;
    // The pane sits in its own route's OverlayEntry, which a plain setState
    // here would not reach.
    _paneEntry.markNeedsBuild();
    widget.onWidthChanged?.call(next);
  }
}

/// The base route of the pane's private Navigator: just the pane's
/// [OverlayEntry], with none of what `ModalRoute` would bring — no barrier
/// (which would block the plant view) and no transition. Routes pushed on top
/// of it by pane content (dropdown menus, dialogs) behave normally.
class _PaneCanvasRoute extends OverlayRoute<void> {
  _PaneCanvasRoute(this._entry);

  final OverlayEntry _entry;

  @override
  Iterable<OverlayEntry> createOverlayEntries() => <OverlayEntry>[_entry];
}
