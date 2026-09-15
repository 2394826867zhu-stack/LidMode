import XCTest

@testable import LidMode

final class PowerStateParserTests: XCTestCase {
  func testParsesNormal() {
    XCTAssertEqual(
      PowerState(pmsetOutput: "System-wide power settings:\n SleepDisabled  0\n"), .normal)
  }

  func testParsesAwake() {
    XCTAssertEqual(PowerState(pmsetOutput: "SleepDisabled 1\n"), .awake)
  }

  func testParsesExtraWhitespace() {
    XCTAssertEqual(PowerState(pmsetOutput: "\t SleepDisabled\t   1   \n"), .awake)
  }

  func testMissingFieldIsUnknown() {
    XCTAssertEqual(PowerState(pmsetOutput: "sleep 1\n"), .unknown)
  }

  func testCompleteNormalOutputWithoutSleepDisabledIsNormal() {
    let output = """
      System-wide power settings:
      Currently in use:
       standby              1
       sleep                1
       displaysleep         10
      """
    XCTAssertEqual(PowerState(pmsetOutput: output), .normal)
  }

  func testMalformedValueIsUnknown() {
    XCTAssertEqual(PowerState(pmsetOutput: "SleepDisabled 2\n"), .unknown)
  }

  func testUnexpectedOutputIsUnknown() {
    XCTAssertEqual(PowerState(pmsetOutput: "not pmset output"), .unknown)
  }

  func testParsesNormalizedHelperOutputOnly() {
    XCTAssertEqual(PowerState(helperOutput: " AWAKE\n"), .awake)
    XCTAssertEqual(PowerState(helperOutput: "NORMAL\n"), .normal)
    XCTAssertEqual(PowerState(helperOutput: "AWAKE extra"), .unknown)
  }

  func testEveryDisplayStateHasACompactMenuBarSymbol() {
    let states: [DisplayState] = [
      .normal, .awake, .executing, .unknown, .setupRequired, .error("test"),
    ]

    for state in states {
      XCTAssertFalse(state.presentation.symbolName.isEmpty)
      XCTAssertFalse(state.presentation.fallbackTitle.isEmpty)
      XCTAssertFalse(state.presentation.statusTitle.isEmpty)
      XCTAssertFalse(state.presentation.accessibilityLabel.isEmpty)
      XCTAssertFalse(state.presentation.toolTip.isEmpty)
    }
  }

  func testNormalAndAwakeUseDistinctMenuBarSymbols() {
    XCTAssertNotEqual(
      DisplayState.normal.presentation.symbolName,
      DisplayState.awake.presentation.symbolName
    )
  }
}
