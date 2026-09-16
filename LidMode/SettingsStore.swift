import Foundation

enum MenuBarTextMode: Int, CaseIterable {
  case always
  case launchOnly

  var title: String {
    switch self {
    case .always: "始终显示状态文字"
    case .launchOnly: "仅启动时显示状态文字"
    }
  }
}

extension Notification.Name {
  static let lidModeSettingsDidChange = Notification.Name("LidModeSettingsDidChange")
}

final class SettingsStore {
  private enum Key {
    static let launchAtLogin = "launchAtLogin"
    static let keepDisplayAwake = "keepDisplayAwake"
    static let batteryProtectionEnabled = "batteryProtectionEnabled"
    static let batteryThreshold = "batteryThreshold"
    static let menuBarTextMode = "menuBarTextMode"
  }

  private let defaults: UserDefaults
  private let notificationCenter: NotificationCenter

  init(
    defaults: UserDefaults = .standard,
    notificationCenter: NotificationCenter = .default
  ) {
    self.defaults = defaults
    self.notificationCenter = notificationCenter
  }

  var launchAtLogin: Bool {
    get { bool(forKey: Key.launchAtLogin, defaultValue: true) }
    set { set(newValue, forKey: Key.launchAtLogin) }
  }

  var keepDisplayAwake: Bool {
    get { bool(forKey: Key.keepDisplayAwake, defaultValue: false) }
    set { set(newValue, forKey: Key.keepDisplayAwake) }
  }

  var batteryProtectionEnabled: Bool {
    get { bool(forKey: Key.batteryProtectionEnabled, defaultValue: true) }
    set { set(newValue, forKey: Key.batteryProtectionEnabled) }
  }

  var batteryThreshold: Int {
    get {
      guard defaults.object(forKey: Key.batteryThreshold) != nil else { return 20 }
      return Self.clampThreshold(defaults.integer(forKey: Key.batteryThreshold))
    }
    set { set(Self.clampThreshold(newValue), forKey: Key.batteryThreshold) }
  }

  var menuBarTextMode: MenuBarTextMode {
    get {
      guard defaults.object(forKey: Key.menuBarTextMode) != nil else { return .always }
      return MenuBarTextMode(rawValue: defaults.integer(forKey: Key.menuBarTextMode)) ?? .always
    }
    set { set(newValue.rawValue, forKey: Key.menuBarTextMode) }
  }

  static func clampThreshold(_ value: Int) -> Int {
    min(50, max(5, value))
  }

  private func bool(forKey key: String, defaultValue: Bool) -> Bool {
    guard defaults.object(forKey: key) != nil else { return defaultValue }
    return defaults.bool(forKey: key)
  }

  private func set(_ value: Any, forKey key: String) {
    defaults.set(value, forKey: key)
    notificationCenter.post(name: .lidModeSettingsDidChange, object: self)
  }
}
