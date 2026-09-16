import Foundation

enum PowerStateServiceError: Error, Equatable {
  case setupRequired
  case permissionDenied
  case helperFailed
  case unreadableState
  case verificationMismatch

  var displayMessage: String {
    switch self {
    case .setupRequired: "需要运行安装脚本"
    case .permissionDenied: "Helper 权限不可用"
    case .helperFailed: "无法修改睡眠状态"
    case .unreadableState: "无法读取系统睡眠状态"
    case .verificationMismatch: "系统状态验证失败"
    }
  }
}

final class PowerStateService {
  typealias StateCompletion = (Result<PowerState, PowerStateServiceError>) -> Void
  typealias SetupCompletion = (PrivilegedHelperSetupResult) -> Void

  private let helperClient: HelperClientProtocol
  private let queue = DispatchQueue(label: "app.lidmode.power-state", qos: .userInitiated)

  init(helperClient: HelperClientProtocol = HelperClient()) {
    self.helperClient = helperClient
  }

  func readState(completion: @escaping StateCompletion) {
    queue.async { [helperClient] in
      completion(Self.readState(using: helperClient))
    }
  }

  func toggle(completion: @escaping StateCompletion) {
    queue.async { [helperClient] in
      let currentResult = Self.readState(using: helperClient)
      guard case .success(let current) = currentResult else {
        completion(currentResult)
        return
      }

      let command: HelperCommand
      let expected: PowerState
      switch current {
      case .normal:
        command = .on
        expected = .awake
      case .awake:
        command = .off
        expected = .normal
      case .unknown:
        completion(.failure(.unreadableState))
        return
      }

      AppLog.power.info("Toggle requested")
      switch helperClient.execute(command) {
      case .success:
        break
      case .failure(let error):
        AppLog.power.error("Helper failed: \(String(describing: error), privacy: .public)")
        _ = Self.readState(using: helperClient)
        completion(.failure(Self.mapToggle(error)))
        return
      }

      let verifiedResult = Self.readState(using: helperClient)
      guard case .success(let verified) = verifiedResult else {
        completion(verifiedResult)
        return
      }
      guard verified == expected else {
        AppLog.power.error("Verification mismatch")
        completion(.failure(.verificationMismatch))
        return
      }

      AppLog.power.info("Toggle verified")
      completion(.success(verified))
    }
  }

  func ensureNormal(completion: @escaping StateCompletion) {
    queue.async { [helperClient] in
      let currentResult = Self.readState(using: helperClient)
      guard case .success(let current) = currentResult else {
        completion(currentResult)
        return
      }
      guard current == .awake else {
        completion(current == .normal ? .success(.normal) : .failure(.unreadableState))
        return
      }

      AppLog.power.info("Normal state requested by policy")
      switch helperClient.execute(.off) {
      case .success:
        break
      case .failure(let error):
        AppLog.power.error("Policy helper failed: \(String(describing: error), privacy: .public)")
        _ = Self.readState(using: helperClient)
        completion(.failure(Self.mapToggle(error)))
        return
      }

      let verifiedResult = Self.readState(using: helperClient)
      guard case .success(let verified) = verifiedResult else {
        completion(verifiedResult)
        return
      }
      guard verified == .normal else {
        AppLog.power.error("Policy verification mismatch")
        completion(.failure(.verificationMismatch))
        return
      }

      AppLog.power.info("Normal state verified")
      completion(.success(.normal))
    }
  }

  func preparePrivilegedHelper(completion: @escaping SetupCompletion) {
    queue.async { [helperClient] in
      completion(helperClient.registerPrivilegedHelper())
    }
  }

  func openPrivilegedHelperSettings() {
    helperClient.openPrivilegedHelperSettings()
  }

  private static func readState(using helperClient: HelperClientProtocol) -> Result<
    PowerState, PowerStateServiceError
  > {
    switch helperClient.execute(.status) {
    case .success(let response):
      let state = PowerState(helperOutput: response.standardOutput)
      guard state != .unknown else {
        AppLog.power.error("State output was not recognized")
        return .failure(.unreadableState)
      }
      AppLog.power.info("System state read")
      return .success(state)
    case .failure(let error):
      AppLog.power.error("State read failed: \(String(describing: error), privacy: .public)")
      return .failure(mapRead(error))
    }
  }

  private static func mapRead(_ error: HelperClientError) -> PowerStateServiceError {
    switch error {
    case .helperMissing:
      .setupRequired
    case .launchFailed:
      .helperFailed
    case .authenticationUnavailable:
      .permissionDenied
    case .timedOut:
      .helperFailed
    case .nonZeroExit(1):
      .permissionDenied
    case .nonZeroExit(3):
      .unreadableState
    case .nonZeroExit:
      .helperFailed
    }
  }

  private static func mapToggle(_ error: HelperClientError) -> PowerStateServiceError {
    switch error {
    case .helperMissing:
      .setupRequired
    case .launchFailed:
      .helperFailed
    case .authenticationUnavailable:
      .permissionDenied
    case .timedOut:
      .helperFailed
    case .nonZeroExit(1):
      .permissionDenied
    case .nonZeroExit(3):
      .verificationMismatch
    case .nonZeroExit:
      .helperFailed
    }
  }
}
