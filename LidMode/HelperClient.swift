import Darwin
import Foundation
import ServiceManagement

enum HelperCommand: String, CaseIterable {
  case on
  case off
  case status

  init?(argument: String) {
    self.init(rawValue: argument)
  }
}

enum HelperClientError: Error, Equatable {
  case helperMissing
  case launchFailed
  case authenticationUnavailable
  case timedOut
  case nonZeroExit(Int32)
}

enum PrivilegedHelperSetupResult: Equatable {
  case enabled
  case requiresApproval
  case unavailable
  case failed
}

struct HelperResponse: Equatable {
  let standardOutput: String
  let standardError: String
}

protocol HelperClientProtocol {
  func execute(_ command: HelperCommand) -> Result<HelperResponse, HelperClientError>
  func registerPrivilegedHelper() -> PrivilegedHelperSetupResult
  func openPrivilegedHelperSettings()
  func unregisterPrivilegedHelper() -> Bool
}

final class HelperClient: HelperClientProtocol {
  static let helperPath = "/usr/local/libexec/lidmode-helper"
  static let commandTimeout: TimeInterval = 5

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func execute(_ command: HelperCommand) -> Result<HelperResponse, HelperClientError> {
    if privilegedService.status == .enabled {
      return executeUsingXPC(command)
    }
    return executeUsingRestrictedSudo(command)
  }

  func registerPrivilegedHelper() -> PrivilegedHelperSetupResult {
    guard CodeSigning.currentTeamIdentifier() != nil else { return .unavailable }

    switch privilegedService.status {
    case .enabled:
      return .enabled
    case .requiresApproval:
      return .requiresApproval
    default:
      break
    }

    do {
      try privilegedService.register()
    } catch {
      return .failed
    }

    switch privilegedService.status {
    case .enabled:
      return .enabled
    case .requiresApproval:
      return .requiresApproval
    default:
      return .failed
    }
  }

  func openPrivilegedHelperSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  func unregisterPrivilegedHelper() -> Bool {
    guard privilegedService.status != .notRegistered else { return true }
    do {
      try privilegedService.unregister()
      return true
    } catch {
      AppLog.lifecycle.error("Privileged helper unregistration failed")
      return false
    }
  }

  private var privilegedService: SMAppService {
    SMAppService.daemon(plistName: HelperConstants.plistName)
  }

  private func executeUsingRestrictedSudo(
    _ command: HelperCommand
  ) -> Result<HelperResponse, HelperClientError> {
    guard fileManager.isExecutableFile(atPath: Self.helperPath) else {
      return .failure(.helperMissing)
    }

    return Self.runProcess(
      executableURL: URL(fileURLWithPath: "/usr/bin/sudo"),
      arguments: ["-n", Self.helperPath, command.rawValue],
      timeout: Self.commandTimeout
    )
  }

  static func runProcess(
    executableURL: URL,
    arguments: [String],
    timeout: TimeInterval
  ) -> Result<HelperResponse, HelperClientError> {
    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    let exited = DispatchSemaphore(value: 0)

    process.executableURL = executableURL
    process.arguments = arguments
    process.standardOutput = standardOutput
    process.standardError = standardError
    process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    process.terminationHandler = { _ in exited.signal() }

    do {
      try process.run()
    } catch {
      return .failure(.launchFailed)
    }

    guard exited.wait(timeout: .now() + timeout) == .success else {
      process.terminate()
      if exited.wait(timeout: .now() + 1) != .success {
        Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
      return .failure(.timedOut)
    }

    let output =
      String(
        data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""
    let errorOutput =
      String(
        data: standardError.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""

    guard process.terminationStatus == 0 else {
      return .failure(.nonZeroExit(process.terminationStatus))
    }

    return .success(HelperResponse(standardOutput: output, standardError: errorOutput))
  }

  private func executeUsingXPC(
    _ command: HelperCommand
  ) -> Result<HelperResponse, HelperClientError> {
    guard
      let requirement = CodeSigning.sameTeamRequirement(
        identifier: HelperConstants.helperIdentifier
      )
    else {
      return .failure(.authenticationUnavailable)
    }

    let connection = NSXPCConnection(
      machServiceName: HelperConstants.machServiceName,
      options: .privileged
    )
    connection.remoteObjectInterface = NSXPCInterface(with: LidModePrivilegedProtocol.self)
    connection.setCodeSigningRequirement(requirement)
    connection.resume()
    defer { connection.invalidate() }

    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var completed = false
    var response: Result<HelperResponse, HelperClientError> = .failure(.launchFailed)

    func finish(_ newResponse: Result<HelperResponse, HelperClientError>) {
      lock.lock()
      defer { lock.unlock() }
      guard !completed else { return }
      completed = true
      response = newResponse
      semaphore.signal()
    }

    let proxy =
      connection.remoteObjectProxyWithErrorHandler { _ in
        finish(.failure(.launchFailed))
      } as? LidModePrivilegedProtocol
    guard let proxy else { return .failure(.launchFailed) }

    let reply: (String, Int32) -> Void = { output, exitCode in
      if exitCode == 0 {
        finish(.success(HelperResponse(standardOutput: output, standardError: "")))
      } else {
        finish(.failure(.nonZeroExit(exitCode)))
      }
    }

    switch command {
    case .status:
      proxy.status(withReply: reply)
    case .on:
      proxy.setDisableSleep(true, withReply: reply)
    case .off:
      proxy.setDisableSleep(false, withReply: reply)
    }

    guard semaphore.wait(timeout: .now() + 5) == .success else {
      return .failure(.timedOut)
    }

    lock.lock()
    defer { lock.unlock() }
    return response
  }
}
