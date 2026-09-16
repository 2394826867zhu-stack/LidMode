import AppKit
import Darwin

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusBarController: StatusBarController?
  private let settings = SettingsStore()
  private let loginItemService = LoginItemService()
  private let helperClient = HelperClient()
  private lazy var powerStateService = PowerStateService(helperClient: helperClient)
  private lazy var displayWakeController = DisplayWakeController()
  private lazy var batteryProtectionController = BatteryProtectionController(
    settings: settings,
    powerStateService: powerStateService
  )
  private lazy var settingsWindowController = SettingsWindowController(
    settings: settings,
    loginItemService: loginItemService
  )
  private var settingsObserver: NSObjectProtocol?
  private var lastPowerState: PowerState = .unknown

  static func main() {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--unregister-login-item") {
      let loginItemRemoved = loginItemService.unregister()
      let helperRemoved = helperClient.unregisterPrivilegedHelper()
      Darwin.exit(loginItemRemoved && helperRemoved ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    if NSClassFromString("XCTestCase") != nil {
      return
    }

    AppLog.lifecycle.info("App started")

    let controller = StatusBarController(
      powerStateService: powerStateService,
      settings: settings,
      onOpenSettings: { [weak self] in self?.settingsWindowController.present() },
      onPowerStateChanged: { [weak self] state in self?.powerStateChanged(state) }
    )
    statusBarController = controller

    settingsObserver = NotificationCenter.default.addObserver(
      forName: .lidModeSettingsDidChange,
      object: settings,
      queue: .main
    ) { [weak self] _ in
      self?.applyRuntimeSettings()
    }

    batteryProtectionController.onNormalRestored = { [weak self] in
      self?.statusBarController?.refresh()
    }
    batteryProtectionController.start()
    controller.refresh()

    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(workspaceDidWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )

    if Bundle.main.bundleURL.path.hasPrefix("/Applications/") {
      _ = loginItemService.setEnabled(settings.launchAtLogin)
    } else {
      AppLog.lifecycle.info("Login item synchronization skipped for development build")
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    if let settingsObserver {
      NotificationCenter.default.removeObserver(settingsObserver)
    }
    batteryProtectionController.stop()
    displayWakeController.release()
  }

  @objc private func workspaceDidWake() {
    AppLog.lifecycle.info("Workspace wake detected")
    statusBarController?.refresh()
    batteryProtectionController.evaluate()
  }

  private func powerStateChanged(_ state: PowerState) {
    lastPowerState = state
    displayWakeController.update(powerState: state, enabled: settings.keepDisplayAwake)
    if state == .awake {
      batteryProtectionController.settingsDidChange()
    }
  }

  private func applyRuntimeSettings() {
    statusBarController?.applySettings()
    displayWakeController.update(
      powerState: lastPowerState,
      enabled: settings.keepDisplayAwake
    )
    batteryProtectionController.settingsDidChange()
  }
}
