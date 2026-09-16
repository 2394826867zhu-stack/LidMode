import Darwin
import Foundation

private enum HelperExit: Int32 {
  case success = 0
  case pmsetFailed = 2
  case verificationFailed = 3
}

final class PrivilegedHelperService: NSObject, LidModePrivilegedProtocol {
  func status(withReply reply: @escaping (String, Int32) -> Void) {
    let state = readState()
    reply(state.0, state.1)
  }

  func setDisableSleep(_ enabled: Bool, withReply reply: @escaping (String, Int32) -> Void) {
    let value = enabled ? "1" : "0"
    let modification = runPMSet(arguments: ["-a", "disablesleep", value])
    guard modification.status == 0 else {
      reply("UNKNOWN", HelperExit.pmsetFailed.rawValue)
      return
    }

    let verified = readState()
    let expected = enabled ? "AWAKE" : "NORMAL"
    guard verified.0 == expected, verified.1 == HelperExit.success.rawValue else {
      reply(verified.0, HelperExit.verificationFailed.rawValue)
      return
    }

    reply(verified.0, verified.1)
  }

  private func readState() -> (String, Int32) {
    let result = runPMSet(arguments: ["-g"])
    guard result.status == 0 else {
      return ("UNKNOWN", HelperExit.pmsetFailed.rawValue)
    }

    let state = PowerState(pmsetOutput: result.output)
    guard state != .unknown else {
      return ("UNKNOWN", HelperExit.verificationFailed.rawValue)
    }
    return (state.helperOutput, HelperExit.success.rawValue)
  }

  private func runPMSet(arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    let standardOutput = Pipe()
    let exited = DispatchSemaphore(value: 0)
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = arguments
    process.standardOutput = standardOutput
    process.standardError = FileHandle.nullDevice
    process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    process.terminationHandler = { _ in exited.signal() }

    do {
      try process.run()
    } catch {
      return (HelperExit.pmsetFailed.rawValue, "")
    }

    guard exited.wait(timeout: .now() + 5) == .success else {
      process.terminate()
      if exited.wait(timeout: .now() + 1) != .success {
        Darwin.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
      }
      return (HelperExit.pmsetFailed.rawValue, "")
    }

    let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }
}

final class PrivilegedHelperLifecycle {
  private let queue = DispatchQueue(label: "app.lidmode.privileged-helper.lifecycle")
  private let idleDelay: TimeInterval
  private let exitHandler: () -> Void
  private var activeConnections = 0
  private var generation: UInt = 0

  init(
    idleDelay: TimeInterval = 10,
    exitHandler: @escaping () -> Void = { Darwin.exit(EXIT_SUCCESS) }
  ) {
    self.idleDelay = idleDelay
    self.exitHandler = exitHandler
  }

  func connectionOpened() {
    queue.sync {
      activeConnections += 1
      generation &+= 1
    }
  }

  func connectionClosed() {
    queue.async { [self] in
      activeConnections = max(0, activeConnections - 1)
      generation &+= 1
      let scheduledGeneration = generation

      queue.asyncAfter(deadline: .now() + idleDelay) { [self] in
        guard activeConnections == 0, generation == scheduledGeneration else { return }
        exitHandler()
      }
    }
  }
}

final class PrivilegedHelperListener: NSObject, NSXPCListenerDelegate {
  private let lifecycle: PrivilegedHelperLifecycle

  init(lifecycle: PrivilegedHelperLifecycle) {
    self.lifecycle = lifecycle
  }

  func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    guard
      let requirement = CodeSigning.sameTeamRequirement(identifier: HelperConstants.appIdentifier)
    else {
      return false
    }

    connection.setCodeSigningRequirement(requirement)
    connection.exportedInterface = NSXPCInterface(with: LidModePrivilegedProtocol.self)
    connection.exportedObject = PrivilegedHelperService()
    lifecycle.connectionOpened()
    connection.invalidationHandler = { [weak lifecycle] in
      lifecycle?.connectionClosed()
    }
    connection.resume()
    return true
  }
}
