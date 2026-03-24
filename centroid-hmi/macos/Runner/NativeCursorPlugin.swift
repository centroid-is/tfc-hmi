import Cocoa
import FlutterMacOS

/// Platform channel plugin that exposes private macOS diagonal resize cursors.
///
/// Flutter's engine maps `SystemMouseCursors.resizeUpLeftDownRight` and
/// `resizeUpRightDownLeft` to the basic arrow on macOS because AppKit's
/// public NSCursor API does not include diagonal resize cursors. The private
/// selectors `_windowResizeNorthWestSouthEastCursor` and
/// `_windowResizeNorthEastSouthWestCursor` provide the native diagonal
/// double-arrow cursors that appear when resizing a Finder window corner.
///
/// This is a SCADA/industrial app — not destined for the App Store — so
/// using private API is acceptable.
class NativeCursorPlugin {
    /// The method channel name shared with the Dart side.
    static let channelName = "com.centroid.native_cursor"

    /// Number of cursors we have pushed onto the stack. Used to balance
    /// push/pop calls so we never pop below the level we started at.
    private static var pushCount = 0

    /// Registers the method-call handler on the given `FlutterViewController`.
    static func register(with controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: controller.engine.binaryMessenger
        )

        channel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "setCursor":
                guard let cursorType = call.arguments as? String else {
                    result(FlutterError(
                        code: "INVALID_ARGUMENT",
                        message: "Expected a String cursor type argument",
                        details: nil
                    ))
                    return
                }
                if let cursor = nativeCursor(for: cursorType) {
                    cursor.push()
                    pushCount += 1
                    result(nil)
                } else {
                    result(FlutterError(
                        code: "UNKNOWN_CURSOR",
                        message: "Unknown cursor type: \(cursorType)",
                        details: nil
                    ))
                }

            case "resetCursor":
                if pushCount > 0 {
                    NSCursor.pop()
                    pushCount -= 1
                }
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Private helpers

    /// Returns the native `NSCursor` for the given type string, using private
    /// AppKit selectors for diagonal resize cursors.
    private static func nativeCursor(for type: String) -> NSCursor? {
        switch type {
        case "resizeNWSE":
            // NW-SE diagonal (top-left / bottom-right corners)
            return cursorFromPrivateSelector("_windowResizeNorthWestSouthEastCursor")
        case "resizeNESW":
            // NE-SW diagonal (top-right / bottom-left corners)
            return cursorFromPrivateSelector("_windowResizeNorthEastSouthWestCursor")
        default:
            return nil
        }
    }

    /// Invokes a private `NSCursor` class method by selector name and returns
    /// the cursor, or `nil` if the selector is not available on this OS version.
    private static func cursorFromPrivateSelector(_ selectorName: String) -> NSCursor? {
        let selector = NSSelectorFromString(selectorName)
        guard NSCursor.responds(to: selector) else { return nil }

        // `perform` returns an `Unmanaged<AnyObject>?`; take the retained value.
        guard let raw = NSCursor.perform(selector) else { return nil }
        return raw.takeUnretainedValue() as? NSCursor
    }
}
