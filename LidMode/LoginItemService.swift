import ServiceManagement

final class LoginItemService {
  @discardableResult
  func register() -> Bool {
    let service = SMAppService.mainApp
    guard service.status == .notRegistered else {
      return service.status == .enabled || service.status == .requiresApproval
    }

    do {
      try service.register()
      AppLog.lifecycle.info("Login item registered")
      return true
    } catch {
      AppLog.lifecycle.error("Login item registration failed")
      return false
    }
  }

  func setEnabled(_ enabled: Bool) -> Bool {
    enabled ? register() : unregister()
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
