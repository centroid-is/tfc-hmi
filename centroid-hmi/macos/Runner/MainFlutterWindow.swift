import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register the native diagonal-resize cursor plugin (uses private
    // NSCursor API for NW-SE / NE-SW cursors that Flutter doesn't expose).
    NativeCursorPlugin.register(with: flutterViewController)

    super.awakeFromNib()
  }
}
