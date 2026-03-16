import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Dispatches gesture events to simulate user interactions.
class GestureDispatcher {
  static const kMaxDelta = 40.0;
  static const kDelay = Duration(milliseconds: 100);

  int _nextPointerId = 1;

  /// Simulates a tap on an element that matches the given [matcher].
  ///
  /// If [matcher] is a [CoordinatesMatcher], taps directly at the specified
  /// coordinates without searching the widget tree (fast path).
  Future<void> tap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    int buttons = kPrimaryButton,
  }) async {
    // Fast path for coordinate-based tapping
    if (matcher is CoordinatesMatcher) {
      await _dispatchTapAtPosition(matcher.offset, buttons: buttons);
      return;
    }

    final element = widgetFinder.findElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    } else {
      await _dispatchTapAtElement(element, buttons: buttons);
    }
  }

  /// Taps directly on a specific [Element] by dispatching pointer events
  /// at its center position. This is used internally by [TextInputSimulator]
  /// to auto-focus text fields before entering text.
  Future<void> tapElement(Element element) async {
    await _dispatchTapAtElement(element);
  }

  Future<void> _dispatchTapAtElement(Element element, {int buttons = kPrimaryButton}) async {
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    // Get the center position of the widget
    final center = renderObject.size.center(Offset.zero);
    final globalPosition = renderObject.localToGlobal(center);

    await _dispatchTapAtPosition(globalPosition, buttons: buttons);
  }

  Future<void> _dispatchTapAtPosition(Offset globalPosition, {int buttons = kPrimaryButton}) async {
    final pointerId = _nextPointerId++;
    final isDesktop = Platform.isMacOS || Platform.isLinux || Platform.isWindows;
    final kind = isDesktop ? PointerDeviceKind.mouse : PointerDeviceKind.touch;

    // Build the event records
    final records = [
      // Add pointer and optionally hover (desktop needs hover before down)
      [
        PointerAddedEvent(position: globalPosition, kind: kind),
        if (isDesktop) PointerHoverEvent(position: globalPosition, kind: kind),
      ],
      // Pointer down
      [
        PointerDownEvent(pointer: pointerId, position: globalPosition, buttons: buttons, kind: kind),
      ],
      // Pointer up after a short delay
      [PointerUpEvent(pointer: pointerId, position: globalPosition, kind: kind)],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Simulates a drag gesture from [from] to [to].
  Future<void> drag(Offset from, Offset to) async {
    final pointerId = _nextPointerId++;

    final delta = to - from;
    final distance = delta.distance;
    final stepCount =
        (distance / kMaxDelta).ceil().clamp(1, double.infinity).toInt();

    final moveRecords = <List<PointerEvent>>[];
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final position = Offset.lerp(from, to, t)!;
      final previousPosition =
          i == 1 ? from : Offset.lerp(from, to, (i - 1) / stepCount)!;
      final stepDelta = position - previousPosition;

      moveRecords.add([
        PointerMoveEvent(
          pointer: pointerId,
          position: position,
          delta: stepDelta,
        ),
      ]);
    }

    final records = [
      [
        PointerAddedEvent(position: from),
        PointerDownEvent(pointer: pointerId, position: from),
      ],
      ...moveRecords,
      [PointerUpEvent(pointer: pointerId, position: to)],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Handles a list of pointer event records by dispatching them with proper timing.
  ///
  /// Similar to Flutter's test framework handlePointerEventRecord, but simplified
  /// for live app execution.
  Future<void> _handlePointerEventRecord(
    List<List<PointerEvent>> records,
  ) async {
    for (final record in records) {
      record.forEach(GestureBinding.instance.handlePointerEvent);
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(kDelay);
    }
  }

  /// Directly invokes the tap/onPressed callback of the nearest tappable ancestor
  /// of the element matched by [matcher], bypassing pointer event dispatch.
  ///
  /// This is useful on platforms (e.g. macOS) where
  /// [GestureBinding.instance.handlePointerEvent] does not reliably trigger
  /// onTap/onPressed callbacks.
  ///
  /// Pass [secondary] = true to invoke the secondary-tap callback (right-click).
  Future<void> directTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    MarionetteConfiguration configuration, {
    bool secondary = false,
  }) async {
    final element = widgetFinder.findElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    // Walk up the element tree from the matched element to find the nearest
    // ancestor (or self) that has a tap/onPressed callback.
    Element? current = element;
    while (current != null) {
      final widget = current.widget;

      if (_tryInvokeCallback(widget, current, secondary: secondary)) {
        WidgetsBinding.instance.scheduleFrame();
        return;
      }

      // Walk to the parent element.
      Element? parent;
      current.visitAncestorElements((ancestor) {
        parent = ancestor;
        return false; // stop after first ancestor
      });
      current = parent;
    }

    throw Exception(
      'No tappable ancestor found for element matching ${matcher.toJson()}',
    );
  }

  /// Attempts to directly invoke the tap/press callback on [widget].
  ///
  /// Returns true if a callback was found and invoked, false otherwise.
  bool _tryInvokeCallback(Widget widget, Element element, {bool secondary = false}) {
    if (widget is FloatingActionButton) {
      if (widget.onPressed != null) {
        widget.onPressed!();
        return true;
      }
    } else if (widget is ElevatedButton) {
      if (widget.onPressed != null) {
        widget.onPressed!();
        return true;
      }
    } else if (widget is TextButton) {
      if (widget.onPressed != null) {
        widget.onPressed!();
        return true;
      }
    } else if (widget is OutlinedButton) {
      if (widget.onPressed != null) {
        widget.onPressed!();
        return true;
      }
    } else if (widget is IconButton) {
      if (widget.onPressed != null) {
        widget.onPressed!();
        return true;
      }
    } else if (widget is InkWell) {
      if (secondary) {
        if (widget.onSecondaryTap != null) {
          widget.onSecondaryTap!();
          return true;
        }
      } else {
        if (widget.onTap != null) {
          widget.onTap!();
          return true;
        }
      }
    } else if (widget is GestureDetector) {
      if (secondary) {
        if (widget.onSecondaryTapUp != null) {
          final position = _getElementCenter(element);
          widget.onSecondaryTapUp!(
            TapUpDetails(
              kind: PointerDeviceKind.mouse,
              globalPosition: position,
              localPosition: position,
            ),
          );
          return true;
        }
        if (widget.onSecondaryTap != null) {
          widget.onSecondaryTap!();
          return true;
        }
      } else {
        if (widget.onTap != null) {
          widget.onTap!();
          return true;
        }
      }
    } else if (widget is ListTile) {
      if (widget.onTap != null) {
        widget.onTap!();
        return true;
      }
    } else if (widget is PopupMenuItem) {
      if (widget.onTap != null) {
        widget.onTap!();
        return true;
      }
    }
    return false;
  }

  /// Returns the global center position of the given [element]'s render object,
  /// or [Offset.zero] if the render object is not a [RenderBox] with a size.
  Offset _getElementCenter(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize) {
      final center = renderObject.size.center(Offset.zero);
      return renderObject.localToGlobal(center);
    }
    return Offset.zero;
  }
}
