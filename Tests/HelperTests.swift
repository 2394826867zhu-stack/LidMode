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
}
