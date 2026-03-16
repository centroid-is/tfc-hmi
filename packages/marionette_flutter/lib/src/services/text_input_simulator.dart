import 'package:flutter/material.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Simulates text input into text fields.
class TextInputSimulator {
  const TextInputSimulator(this._widgetFinder, this._gestureDispatcher);

  final WidgetFinder _widgetFinder;
  final GestureDispatcher _gestureDispatcher;

  /// Enters text into a text field identified by the given matcher.
  ///
  /// Automatically taps the widget first to ensure it has focus before
  /// entering text. Without focus, the text input may silently fail
  /// because Flutter's text input connection is not active.
  Future<void> enterText(
    WidgetMatcher matcher,
    String text,
    MarionetteConfiguration configuration,
  ) async {
    final element = _widgetFinder.findElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    // Auto-focus: tap the widget first to ensure it has an active text
    // input connection. Without this, entering text silently fails because
    // Flutter's EditableText only establishes a TextInputConnection when
    // it receives focus.
    //
    // On macOS (and some other desktop platforms) the pointer event dispatch
    // path raises a MouseTracker assertion error. We swallow that error and
    // fall through to the controller.text direct-set path below, which does
    // not require an active TextInputConnection.
    try {
      await _gestureDispatcher.tapElement(element);
    } catch (_) {
      // Ignore focus-tap failures (e.g. macOS mouse-tracker assertion).
      // The EditableText controller update below will still work.
    }

    // Wait for the tap to be processed and focus to be established.
    // The frame scheduled by the tap needs to complete, and then the
    // text input connection needs to be opened.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Re-find the element after the tap, as the widget tree may have
    // rebuilt in response to gaining focus.
    final freshElement = _widgetFinder.findElement(matcher, configuration);
    if (freshElement == null) {
      throw Exception(
        'Element matching ${matcher.toJson()} not found after focus tap',
      );
    }

    // Try to find the EditableText widget within the matched element's subtree
    final editableTextElement = _widgetFinder.findElementFrom(
      const TypeMatcher(EditableText),
      freshElement,
      configuration,
    );

    if (editableTextElement != null) {
      final editableText = editableTextElement.widget as EditableText;

      // Update the controller directly
      editableText.controller
        ..text = text
        // Move cursor to end
        ..selection = TextSelection.collapsed(offset: text.length);

      // Schedule a frame to ensure the UI updates
      WidgetsBinding.instance.scheduleFrame();
      return;
    }

    throw Exception(
      'Could not find an EditableText widget within the subtree of matcher ${matcher.toJson()}',
    );
  }
}
