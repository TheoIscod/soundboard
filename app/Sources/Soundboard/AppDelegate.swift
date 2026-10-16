import AppKit

/// Receives sets opened from Finder (double-click, Open With) or dropped on the Dock icon,
/// and soundboard:// links (e.g. from Shortcuts).
/// They can arrive before the board is ready when the open launches the app, so they wait
/// until a handler is set.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var openHandler: (([URL]) -> Void)? {
    didSet { deliverPendingURLs() }
  }

  private var pendingURLs: [URL] = []
  /// Runs before the app quits, e.g. to write changes still waiting to be saved.
  var terminateHandler: (() -> Void)?

  func applicationWillTerminate(_ notification: Notification) {
    terminateHandler?()
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    pendingURLs += urls
    deliverPendingURLs()
  }

  private func deliverPendingURLs() {
    guard let openHandler, !pendingURLs.isEmpty else { return }
    let urls = pendingURLs
    pendingURLs = []
    openHandler(urls)
  }
}
