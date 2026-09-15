import Darwin
import Foundation

private enum HelperExit: Int32, Error {
  case success = 0
  case invalidArgument = 1
  case pmsetFailed = 2
  case verificationFailed = 3
}

private enum HelperAction: String {
  case on
  case off
  case status
}

@main
private struct LidModeHelper {
  static func main() {
    guard
      CommandLine.arguments.count == 2,
      let action = HelperAction(rawValue: CommandLine.arguments[1])
    else {
      writeError("usage: lidmode-helper on|off|status")
      Darwin.exit(HelperExit.invalidArgument.rawValue)
    }

    switch action {
    case .status:
      reportStatus()
    case .on:
      changeState(to: .awake, value: "1")
    case .off:
      changeState(to: .normal, value: "0")
    }
  }

  private static func reportStatus() {
    switch readState() {
    case .success(let state):
      print(state.helperOutput)
      Darwin.exit(HelperExit.success.rawValue)
    case .failure(let error):
      print(PowerState.unknown.helperOutput)
      Darwin.exit(error.rawValue)
    }
  }

  private static func changeState(to expected: PowerState, value: String) {
    let result = runPMSet(arguments: ["-a", "disablesleep", value])
    guard result.status == 0 else {
      writeError("pmset failed")
      Darwin.exit(HelperExit.pmsetFailed.rawValue)
    }

    guard case .success(let actual) = readState(), actual == expected else {
      writeError("state verification failed")
      Darwin.exit(HelperExit.verificationFailed.rawValue)
    }

    print(expected.helperOutput)
    Darwin.exit(HelperExit.success.rawValue)
  }

  private static func readState() -> Result<PowerState, HelperExit> {
    let result = runPMSet(arguments: ["-g"])
    guard result.status == 0 else { return .failure(.pmsetFailed) }

    let state = PowerState(pmsetOutput: result.output)
    guard state != .unknown else { return .failure(.verificationFailed) }
    return .success(state)
  }

  private static func runPMSet(arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return (HelperExit.pmsetFailed.rawValue, "")
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output)
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }
}
