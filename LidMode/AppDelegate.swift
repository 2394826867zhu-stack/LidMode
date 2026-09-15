import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusBarController: StatusBarController?
  private let loginItemService = LoginItemService()
  private let helperClient = HelperClient()

  func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--unregister-login-item") {
      loginItemService.unregister()
      helperClient.unregisterPrivilegedHelper()
      NSApp.terminate(nil)
      return
    }

    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
      return
    }

    NSApp.setActivationPolicy(.accessory)
    AppLog.lifecycle.info("App started")

    let controller = StatusBarController(powerStateService: PowerStateService())
    statusBarController = controller
    controller.refresh()

    NSWorkspace.shared.notificationCenter.addObserver(
      self,
      selector: #selector(workspaceDidWake),
      name: NSWorkspace.didWakeNotification,
      object: nil
    )

    if Bundle.main.bundleURL.path.hasPrefix("/Applications/") {
      loginItemService.register()
    } else {
      AppLog.lifecycle.info("Login item registration skipped for development build")
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  @objc private func workspaceDidWake() {
    AppLog.lifecycle.info("Workspace wake detected")
    statusBarController?.refresh()
  }
}
