import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pane_chrome.dart';

/// The standard popup window: same header, body and pinned action bar as
/// [SidePane], in a rectangle instead of a dock.
///
/// It comes in two flavours, and the choice is about what the operator is
/// doing, not about how much content there is:
///
///  * [showStandardDialog] — **modal**. A centred window with a barrier, for
///    short interactions that must finish before anything else happens:
///    confirmations, a single parameter edit, an error the operator must
///    acknowledge. Returns a value, so it is a drop-in for `showDialog`.
///
///  * [showFloatingDialog] — **free-floating**. A draggable, resizable window
///    with no barrier that the operator can push aside and leave open next to
///    the live plant view. This is what a [PaneGraphTile] or [PaneExpandTile]
///    opens when a trend or a channel grid is too big for the side pane.
///
/// Complicated equipment popups belong in a [SidePane]; reach for a dialog
/// when the content is genuinely wider than a pane (charts, I/O grids,
/// tables) or when you need an answer back.
class StandardDialog extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final PaneStatus? status;
  final List<PaneAction> actions;
  final Widget child;
  final VoidCallback? onClose;
  final String closeLabel;
  final Widget? headerTrailing;

  /// Wraps the header, used by the floating variant to make it a drag handle.
  final Widget Function(BuildContext context, Widget header)? headerWrap;

  /// Whether the body scrolls when it does not fit.
  final bool scrollable;

  const StandardDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.status,
    this.actions = const [],
    this.onClose,
    this.closeLabel = 'Close',
    this.headerTrailing,
    this.headerWrap,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: child,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PaneHeader(
          title: title,
          subtitle: subtitle,
          icon: icon,
          status: status,
          onClose: onClose,
          trailing: headerTrailing,
          wrap: headerWrap,
        ),
        Flexible(
          child: scrollable
              ? SingleChildScrollView(primary: false, child: body)
              : body,
        ),
        PaneActionBar(
          actions: actions,
          onClose: onClose,
          closeLabel: closeLabel,
        ),
      ],
    );
  }
}

/// A [StandardDialog] in a modal frame, for widget classes that ARE the
/// argument to `showDialog` rather than a call to [showStandardDialog].
///
/// This is the drop-in replacement for `AlertDialog` in a class whose
/// `build` returns the dialog itself:
///
/// ```dart
/// // was: AlertDialog(title: Text('Edit key'), content: body, actions: [...])
/// StandardDialogFrame(title: 'Edit key', actions: [...], child: body)
/// ```
class StandardDialogFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final PaneStatus? status;
  final List<PaneAction> actions;
  final Widget child;
  final String closeLabel;

  /// Omit the automatic Close — for dialogs whose own actions already cover
  /// dismissal (Cancel/Save), where a third button would just be noise.
  final bool showClose;

  final double width;
  final double? height;
  final bool scrollable;

  const StandardDialogFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.status,
    this.actions = const [],
    this.closeLabel = 'Close',
    this.showClose = true,
    this.width = 520,
    this.height,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = height ?? MediaQuery.sizeOf(context).height * 0.8;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: SizedBox(
          width: width,
          height: height,
          child: StandardDialog(
            title: title,
            subtitle: subtitle,
            icon: icon,
            status: status,
            actions: actions,
            closeLabel: closeLabel,
            scrollable: scrollable,
            onClose: showClose ? () => Navigator.of(context).pop() : null,
            child: child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modal
// ---------------------------------------------------------------------------

/// Shows a modal [StandardDialog] and completes with the value the dialog is
/// popped with.
///
/// [actionsBuilder] receives the dialog's own context, so an action can pop a
/// result:
///
/// ```dart
/// final ok = await showStandardDialog<bool>(
///   context: context,
///   title: 'Reset run hours',
///   builder: (_) => const Text('Run hours will be set to zero.'),
///   actionsBuilder: (ctx) => [
///     PaneAction.destructive(
///       label: 'Reset',
///       onPressed: () => Navigator.of(ctx).pop(true),
///     ),
///   ],
/// );
/// ```
Future<T?> showStandardDialog<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  IconData? icon,
  PaneStatus? status,
  List<PaneAction> Function(BuildContext context)? actionsBuilder,
  double width = 520,
  double? height,
  bool barrierDismissible = true,
  String closeLabel = 'Close',

  /// For callers that live ABOVE the app Navigator — overlay-hosted widgets
  /// like the chat window, whose own context has no Navigator to push onto.
  bool useRootNavigator = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    builder: (dialogContext) => Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: height ?? MediaQuery.sizeOf(dialogContext).height * 0.8,
        ),
        child: SizedBox(
          width: width,
          height: height,
          child: StandardDialog(
            title: title,
            subtitle: subtitle,
            icon: icon,
            status: status,
            actions: actionsBuilder?.call(dialogContext) ?? const [],
            closeLabel: closeLabel,
            onClose: () => Navigator.of(dialogContext).pop(),
            child: builder(dialogContext),
          ),
        ),
      ),
    ),
  );
}

/// The confirm/cancel prompt, once.
///
/// Returns true only if the operator confirmed; a dismissed dialog is `false`,
/// never null, so callers do not have to handle three outcomes for a
/// two-outcome question.
///
/// Set [destructive] for anything that deletes, resets or stops something —
/// it colours the confirm action with the error colour.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
  bool autofocusConfirm = false,
}) async {
  final result = await showStandardDialog<bool>(
    context: context,
    title: title,
    icon: icon ?? (destructive ? Icons.warning_amber : Icons.help_outline),
    closeLabel: cancelLabel,
    builder: (_) => Text(message),
    actionsBuilder: (dialogContext) => [
      destructive
          ? PaneAction.destructive(
              label: confirmLabel,
              autofocus: autofocusConfirm,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            )
          : PaneAction.primary(
              label: confirmLabel,
              autofocus: autofocusConfirm,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
    ],
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------
// Free-floating
// ---------------------------------------------------------------------------

/// Opens a free-floating, draggable, resizable [StandardDialog].
///
/// Nothing is dimmed and nothing is blocked — the plant view keeps running
/// behind it and several floating dialogs can be open at once (a trend for
/// each of two conveyors, say). [id] de-duplicates: opening an id that is
/// already showing is a no-op rather than a second copy.
void showFloatingDialog({
  required BuildContext context,
  required String id,
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  IconData? icon,
  PaneStatus? status,
  List<PaneAction> actions = const [],
  Size size = const Size(640, 480),
  Offset? position,
  String closeLabel = 'Close',
  VoidCallback? onClosed,

  /// Set false for content that fills the window itself — a chart with an
  /// `Expanded` inside cannot lay out against a scroll view's unbounded
  /// height, and a chart wants the whole window anyway.
  bool scrollable = true,
}) {
  FloatingDialogs._show(
    context: context,
    id: id,
    title: title,
    subtitle: subtitle,
    icon: icon,
    status: status,
    actions: actions,
    builder: builder,
    size: size,
    position: position,
    closeLabel: closeLabel,
    onClosed: onClosed,
    scrollable: scrollable,
  );
}

/// Closes the floating dialog with this [id], if it is open.
void closeFloatingDialog(String id) => FloatingDialogs.close(id);

/// Registry of open floating dialogs.
///
/// Public so the side pane can tell whether an Escape key press belongs to a
/// dialog on top of it, and so tests can assert on what is open.
abstract final class FloatingDialogs {
  static final Map<String, OverlayEntry> _entries = {};

  /// Ids in the order they were opened; the last one is the newest.
  static final List<String> _stack = [];

  static bool get isEmpty => _stack.isEmpty;

  static List<String> get openIds => List.unmodifiable(_stack);

  static bool isOpen(String id) => _entries.containsKey(id);

  static void _show({
    required BuildContext context,
    required String id,
    required String title,
    required WidgetBuilder builder,
    String? subtitle,
    IconData? icon,
    PaneStatus? status,
    List<PaneAction> actions = const [],
    Size size = const Size(640, 480),
    Offset? position,
    String closeLabel = 'Close',
    VoidCallback? onClosed,
    bool scrollable = true,
  }) {
    if (_entries.containsKey(id)) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    // Cascade so a second dialog does not land exactly on the first.
    final cascade = _stack.length * 28.0;
    final entry = OverlayEntry(
      builder: (context) => _FloatingDialogShell(
        id: id,
        title: title,
        subtitle: subtitle,
        icon: icon,
        status: status,
        actions: actions,
        closeLabel: closeLabel,
        initialSize: size,
        initialPosition: position,
        cascade: cascade,
        scrollable: scrollable,
        builder: builder,
      ),
    );
    _entries[id] = entry;
    _stack.add(id);
    _onClosed[id] = onClosed;
    overlay.insert(entry);
  }

  static final Map<String, VoidCallback?> _onClosed = {};

  static void close(String id) {
    final entry = _entries.remove(id);
    _stack.remove(id);
    entry?.remove();
    _onClosed.remove(id)?.call();
  }

  /// Drops the bookkeeping for a dialog whose overlay went away on its own —
  /// a route change, a hot restart, a test's next `pumpWidget`. Without this
  /// the id would stay "open" forever and never show again.
  static void _forget(String id) {
    if (!_entries.containsKey(id)) return;
    _entries.remove(id);
    _stack.remove(id);
    _onClosed.remove(id)?.call();
  }

  /// Closes the most recently opened dialog. Returns false if none was open.
  static bool closeTop() {
    if (_stack.isEmpty) return false;
    close(_stack.last);
    return true;
  }
}

/// Geometry, dragging, resizing and Escape handling for a floating dialog.
class _FloatingDialogShell extends StatefulWidget {
  final String id;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final PaneStatus? status;
  final List<PaneAction> actions;
  final String closeLabel;
  final Size initialSize;
  final Offset? initialPosition;
  final double cascade;
  final bool scrollable;
  final WidgetBuilder builder;

  const _FloatingDialogShell({
    required this.id,
    required this.title,
    required this.actions,
    required this.closeLabel,
    required this.initialSize,
    required this.cascade,
    required this.builder,
    this.scrollable = true,
    this.subtitle,
    this.icon,
    this.status,
    this.initialPosition,
  });

  @override
  State<_FloatingDialogShell> createState() => _FloatingDialogShellState();
}

class _FloatingDialogShellState extends State<_FloatingDialogShell> {
  static const Size _minSize = Size(320, 240);

  Offset? _position;
  late Size _size = widget.initialSize;
  Size _screen = Size.zero;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    FloatingDialogs._forget(widget.id);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    // Only the newest dialog reacts, so Escape peels the stack one at a time.
    if (FloatingDialogs._stack.isEmpty ||
        FloatingDialogs._stack.last != widget.id) {
      return false;
    }
    FloatingDialogs.close(widget.id);
    return true;
  }

  void _clamp() {
    final maxX = (_screen.width - _size.width).clamp(0.0, double.infinity);
    final maxY = (_screen.height - _size.height).clamp(0.0, double.infinity);
    _position = Offset(
      _position!.dx.clamp(0.0, maxX),
      _position!.dy.clamp(0.0, maxY),
    );
  }

  @override
  Widget build(BuildContext context) {
    _screen = MediaQuery.sizeOf(context);

    // Shrink to fit small windows before deciding where to put it.
    _size = Size(
      _size.width.clamp(
        _minSize.width,
        _screen.width < _minSize.width ? _minSize.width : _screen.width,
      ),
      _size.height.clamp(
        _minSize.height,
        _screen.height < _minSize.height ? _minSize.height : _screen.height,
      ),
    );

    _position ??= widget.initialPosition ??
        Offset(
          (_screen.width - _size.width) / 2 + widget.cascade,
          (_screen.height - _size.height) / 2 + widget.cascade,
        );
    _clamp();

    return Positioned(
      left: _position!.dx,
      top: _position!.dy,
      child: SizedBox(
        width: _size.width,
        height: _size.height,
        // Not resizable: a floating dialog is sized by whoever opens it —
        // a chart asks for chart-sized, a grid for grid-sized — and it
        // shrinks itself to fit a smaller window. Drag handles on every edge
        // bought fiddly targets around content the operator is aiming at.
        child: Material(
          // Matches SidePane: outline, not shadow (see side_pane.dart). A
          // floating window keeps a touch of elevation so it reads as
          // sitting above the pane it came from.
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          color: Theme.of(context).colorScheme.surface,
          clipBehavior: Clip.antiAlias,
          child: StandardDialog(
            title: widget.title,
            subtitle: widget.subtitle,
            icon: widget.icon,
            status: widget.status,
            actions: widget.actions,
            closeLabel: widget.closeLabel,
            scrollable: widget.scrollable,
            onClose: () => FloatingDialogs.close(widget.id),
            // The header doubles as the window's title bar.
            headerWrap: (context, header) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (d) => setState(() {
                _position = _position! + d.delta;
                _clamp();
              }),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: header,
              ),
            ),
            child: widget.builder(context),
          ),
        ),
      ),
    );
  }
}
