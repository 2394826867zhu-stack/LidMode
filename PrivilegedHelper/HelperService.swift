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
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = arguments
    process.standardOutput = standardOutput
    process.standardError = FileHandle.nullDevice
    process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return (HelperExit.pmsetFailed.rawValue, "")
    }

    let data = standardOutput.fileHandleForReading.readDataToEndOfFile()
    return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }
}

final class PrivilegedHelperListener: NSObject, NSXPCListenerDelegate {
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
    connection.resume()
    return true
  }
}
