import XCTest

@testable import LidMode

final class HelperTests: XCTestCase {
  func testCommandAllowlist() {
    XCTAssertEqual(HelperCommand(argument: "on"), .on)
    XCTAssertEqual(HelperCommand(argument: "off"), .off)
    XCTAssertEqual(HelperCommand(argument: "status"), .status)
  }

  func testRejectsArbitraryArguments() {
    XCTAssertNil(HelperCommand(argument: ""))
    XCTAssertNil(HelperCommand(argument: "on;whoami"))
    XCTAssertNil(HelperCommand(argument: "/bin/sh"))
    XCTAssertNil(HelperCommand(argument: "status extra"))
  }

  func testHelperPathIsAbsoluteAndFixed() {
    XCTAssertEqual(HelperClient.helperPath, "/usr/local/libexec/lidmode-helper")
    XCTAssertTrue(HelperClient.helperPath.hasPrefix("/"))
  }

  func testProcessRunnerCapturesOutput() throws {
    let result = HelperClient.runProcess(
      executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
      arguments: ["NORMAL\n"],
      timeout: 1
    )

    XCTAssertEqual(try result.get().standardOutput, "NORMAL\n")
  }

  func testProcessRunnerTimesOut() {
    let started = Date()
    let result = HelperClient.runProcess(
      executableURL: URL(fileURLWithPath: "/bin/sleep"),
      arguments: ["2"],
      timeout: 0.05
    )

    XCTAssertEqual(result, .failure(.timedOut))
    XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
  }
}

final class PowerStateServiceTests: XCTestCase {
  func testReadsNormalizedState() {
    let client = ScriptedHelperClient([.success(response("NORMAL\n"))])
    let service = PowerStateService(helperClient: client)
    let completed = expectation(description: "state read")

    service.readState { result in
      XCTAssertEqual(result, .success(.normal))
      completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
    XCTAssertEqual(client.commands, [.status])
  }

  func testToggleReadsModifiesAndVerifies() {
    let client = ScriptedHelperClient([
      .success(response("NORMAL")),
      .success(response("AWAKE")),
      .success(response("AWAKE")),
    ])
    let service = PowerStateService(helperClient: client)
    let completed = expectation(description: "toggle")

    service.toggle { result in
      XCTAssertEqual(result, .success(.awake))
      completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
    XCTAssertEqual(client.commands, [.status, .on, .status])
  }

  func testToggleRereadsAfterCommandFailure() {
    let client = ScriptedHelperClient([
      .success(response("NORMAL")),
      .failure(.nonZeroExit(2)),
      .success(response("NORMAL")),
    ])
    let service = PowerStateService(helperClient: client)
    let completed = expectation(description: "failed toggle")

    service.toggle { result in
      XCTAssertEqual(result, .failure(.helperFailed))
      completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
    XCTAssertEqual(client.commands, [.status, .on, .status])
  }

  func testToggleRejectsVerificationMismatch() {
    let client = ScriptedHelperClient([
      .success(response("NORMAL")),
      .success(response("AWAKE")),
      .success(response("NORMAL")),
    ])
    let service = PowerStateService(helperClient: client)
    let completed = expectation(description: "mismatch")

    service.toggle { result in
      XCTAssertEqual(result, .failure(.verificationMismatch))
      completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
  }

  func testMapsMissingHelperToSetupRequired() {
    let client = ScriptedHelperClient([.failure(.helperMissing)])
    let service = PowerStateService(helperClient: client)
    let completed = expectation(description: "missing helper")

    service.readState { result in
      XCTAssertEqual(result, .failure(.setupRequired))
      completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
  }

  func testEnsureNormalDoesNothingWhenAlreadyNormal() {
    let client = ScriptedHelperClient([.success(response("NORMAL"))])
    let service = PowerStateService(helperClient: client)
    let completed = expectation(description: "already normal")

    service.ensureNormal { result in
      XCTAssertEqual(result, .success(.normal))
      completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
    XCTAssertEqual(client.commands, [.status])
  }

  func testEnsureNormalTurnsAwakeOffAndVerifies() {
    let client = ScriptedHelperClient([
      .success(response("AWAKE")),
      .success(response("NORMAL")),
      .success(response("NORMAL")),
    ])
    let service = PowerStateService(helperClient: client)
    let completed = expectation(description: "restore normal")

    service.ensureNormal { result in
      XCTAssertEqual(result, .success(.normal))
      completed.fulfill()
    }

    wait(for: [completed], timeout: 1)
    XCTAssertEqual(client.commands, [.status, .off, .status])
  }

  private func response(_ output: String) -> HelperResponse {
    HelperResponse(standardOutput: output, standardError: "")
  }
}

final class SettingsStoreTests: XCTestCase {
  private var suiteName = ""
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    suiteName = "LidModeTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    defaults.removePersistentDomain(forName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  func testDefaultsMatchSafeProductDefaults() {
    let store = SettingsStore(defaults: defaults)

    XCTAssertTrue(store.launchAtLogin)
    XCTAssertFalse(store.keepDisplayAwake)
    XCTAssertTrue(store.batteryProtectionEnabled)
    XCTAssertEqual(store.batteryThreshold, 20)
    XCTAssertEqual(store.menuBarTextMode, .always)
  }

  func testBatteryThresholdIsClamped() {
    let store = SettingsStore(defaults: defaults)

    store.batteryThreshold = 1
    XCTAssertEqual(store.batteryThreshold, 5)
    store.batteryThreshold = 99
    XCTAssertEqual(store.batteryThreshold, 50)
  }
}

final class BatteryProtectionPolicyTests: XCTestCase {
  func testProtectsAtOrBelowThresholdOnlyOnBattery() {
    XCTAssertTrue(
      BatteryProtectionPolicy.shouldRestoreNormal(
        snapshot: BatterySnapshot(percentage: 20, isOnBattery: true),
        enabled: true,
        threshold: 20
      )
    )
    XCTAssertFalse(
      BatteryProtectionPolicy.shouldRestoreNormal(
        snapshot: BatterySnapshot(percentage: 21, isOnBattery: true),
        enabled: true,
        threshold: 20
      )
    )
    XCTAssertFalse(
      BatteryProtectionPolicy.shouldRestoreNormal(
        snapshot: BatterySnapshot(percentage: 10, isOnBattery: false),
        enabled: true,
        threshold: 20
      )
    )
    XCTAssertFalse(
      BatteryProtectionPolicy.shouldRestoreNormal(
        snapshot: BatterySnapshot(percentage: 10, isOnBattery: true),
        enabled: false,
        threshold: 20
      )
    )
  }
}

private final class ScriptedHelperClient: HelperClientProtocol {
  private let lock = NSLock()
  private var responses: [Result<HelperResponse, HelperClientError>]
  private(set) var commands: [HelperCommand] = []

  init(_ responses: [Result<HelperResponse, HelperClientError>]) {
    self.responses = responses
  }

  func execute(_ command: HelperCommand) -> Result<HelperResponse, HelperClientError> {
    lock.lock()
    defer { lock.unlock() }
    commands.append(command)
    guard !responses.isEmpty else { return .failure(.launchFailed) }
    return responses.removeFirst()
  }

  func registerPrivilegedHelper() -> PrivilegedHelperSetupResult { .enabled }
  func openPrivilegedHelperSettings() {}
  func unregisterPrivilegedHelper() -> Bool { true }
}
