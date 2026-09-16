import AppKit
import Darwin

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusBarController: StatusBarController?
  private let loginItemService = LoginItemService()
  private let helperClient = HelperClient()

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
