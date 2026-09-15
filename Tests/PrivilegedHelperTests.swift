import Foundation
import XCTest

@testable import LidMode

final class PrivilegedHelperTests: XCTestCase {
  func testIdentifiersAreFixedAndDistinct() {
    XCTAssertEqual(
      HelperConstants.appIdentifier,
      "io.github.2394826867zhu-stack.LidMode"
    )
    XCTAssertEqual(HelperConstants.helperIdentifier, "app.lidmode.PrivilegedHelper")
    XCTAssertEqual(HelperConstants.machServiceName, HelperConstants.helperIdentifier)
    XCTAssertNotEqual(HelperConstants.appIdentifier, HelperConstants.helperIdentifier)
  }

  func testHelperIsEmbeddedWithLaunchDaemonPropertyList() throws {
    let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
    let helper = contents.appendingPathComponent("MacOS/LidModePrivilegedHelper")
    let propertyList = contents.appendingPathComponent(
      "Library/LaunchDaemons/app.lidmode.PrivilegedHelper.plist"
    )

    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: propertyList.path))

    let data = try Data(contentsOf: propertyList)
    let decoded = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
    XCTAssertEqual(decoded["Label"] as? String, HelperConstants.helperIdentifier)
    XCTAssertEqual(decoded["BundleProgram"] as? String, "Contents/MacOS/LidModePrivilegedHelper")
  }
}
