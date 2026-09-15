import Foundation

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
  case nonZeroExit(Int32)
}

struct HelperResponse: Equatable {
  let standardOutput: String
  let standardError: String
}

final class HelperClient {
  static let helperPath = "/usr/local/libexec/lidmode-helper"

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func execute(_ command: HelperCommand) -> Result<HelperResponse, HelperClientError> {
    guard fileManager.isExecutableFile(atPath: Self.helperPath) else {
      return .failure(.helperMissing)
    }

    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    process.arguments = ["-n", Self.helperPath, command.rawValue]
    process.standardOutput = standardOutput
    process.standardError = standardError
    process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return .failure(.launchFailed)
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

    return .success(
      HelperResponse(
        standardOutput: output,
        standardError: errorOutput
      ))
  }
}
