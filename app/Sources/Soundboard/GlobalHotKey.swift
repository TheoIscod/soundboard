import AppKit
import Carbon.HIToolbox
import SoundboardCore
import os

/// Brings the app forward with its main window, from anywhere (global shortcut, OSC).
@MainActor
enum AppActivation {
  static func bringForward() {
    NSApp.unhide(nil)
    for window in NSApp.windows where window.isMiniaturized { window.deminiaturize(nil) }
    NSApp.windows.first { $0.canBecomeMain && $0.isVisible }?.makeKeyAndOrderFront(nil)
    // Since macOS 14 a background app asking to activate itself is ignored. Asking Launch
    // Services to open the app, which is already running, brings it forward instead.
    let bundleURL = Bundle.main.bundleURL
    if bundleURL.pathExtension == "app" {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
    } else {
      // `make run` has no bundle to open; activation works there while launched from a terminal.
      NSApp.activate()
    }
  }
}

/// The system-wide shortcut that brings the app forward. Uses Carbon's RegisterEventHotKey,
/// which needs no Accessibility permission, unlike watching every key press.
@MainActor
@Observable
final class GlobalHotKey {
  private static let defaultsKey = "globalShortcut"
  /// Four-character code identifying our hot keys to Carbon ("SNDB").
  private static let signature: OSType = 0x534E_4442
  private static let log = Logger(subsystem: "io.github.theoiscod.soundboard", category: "hotkey")

  var shortcut: GlobalShortcut? {
    didSet {
      save()
      register()
    }
  }
  /// Why the shortcut isn't active, e.g. another app already uses it.
  private(set) var problem: String?

  @ObservationIgnored private var hotKey: EventHotKeyRef?
  @ObservationIgnored private var handler: EventHandlerRef?

  init() {
    shortcut = UserDefaults.standard.data(forKey: Self.defaultsKey)
      .flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) }
    installHandler()
    register()
  }

  private func save() {
    guard let shortcut else {
      UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
      return
    }
    do {
      UserDefaults.standard.set(try JSONEncoder().encode(shortcut), forKey: Self.defaultsKey)
    } catch {
      problem = "Impossible d’enregistrer le raccourci : \(error.localizedDescription)"
    }
  }

  /// Safe to call repeatedly: the previous registration is always removed first.
  private func register() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    problem = nil
    guard let shortcut else { return }

    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      Self.carbonModifiers(shortcut.modifiers),
      EventHotKeyID(signature: Self.signature, id: 1),
      GetApplicationEventTarget(),
      0,
      &reference
    )
    Self.log.info("Global shortcut \(shortcut.displayName, privacy: .public): status \(status)")
    if status == noErr {
      hotKey = reference
    } else if status == eventHotKeyExistsErr {
      problem = "Ce raccourci est déjà utilisé par une autre app ou par macOS."
    } else {
      problem = "Le raccourci n’a pas pu être activé (erreur \(status))."
    }
  }

  private func installHandler() {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    // A C callback can't capture anything; ours has a single job, so it needs no context.
    InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &eventType, nil, &handler)
  }

  private static func carbonModifiers(_ modifiers: Set<GlobalShortcut.Modifier>) -> UInt32 {
    var mask = 0
    if modifiers.contains(.command) { mask |= cmdKey }
    if modifiers.contains(.option) { mask |= optionKey }
    if modifiers.contains(.control) { mask |= controlKey }
    if modifiers.contains(.shift) { mask |= shiftKey }
    return UInt32(mask)
  }
}

/// Carbon delivers hot key events on the main thread; hop to the main actor explicitly.
private func hotKeyPressed(
  _ handler: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  Task { @MainActor in AppActivation.bringForward() }
  return noErr
}
