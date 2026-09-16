import ServiceManagement

final class LoginItemService {
  func register() {
    let service = SMAppService.mainApp
    guard service.status == .notRegistered else { return }

    do {
      try service.register()
      AppLog.lifecycle.info("Login item registered")
    } catch {
      AppLog.lifecycle.error("Login item registration failed")
    }
  }

  func unregister() -> Bool {
    let service = SMAppService.mainApp
    guard service.status != .notRegistered else { return true }

    do {
      try service.unregister()
      AppLog.lifecycle.info("Login item unregistered")
      return true
    } catch {
      AppLog.lifecycle.error("Login item unregistration failed")
      return false
    }
  }
}
