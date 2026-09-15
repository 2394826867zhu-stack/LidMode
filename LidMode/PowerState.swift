import Foundation

enum PowerState: Equatable {
  case normal
  case awake
  case unknown

  init(pmsetOutput: String) {
    let pattern = #"(?im)^\s*SleepDisabled\s+([01])\s*$"#
    if let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: pmsetOutput,
        range: NSRange(pmsetOutput.startIndex..., in: pmsetOutput)
      ),
      let valueRange = Range(match.range(at: 1), in: pmsetOutput)
    {
      switch pmsetOutput[valueRange] {
      case "0": self = .normal
      case "1": self = .awake
      default: self = .unknown
      }
      return
    }

    // On current macOS releases, `pmset -g` omits SleepDisabled entirely
    // when it is at the default value (0). Only infer Normal from a
    // structurally complete `pmset -g` response; partial or arbitrary
    // output remains Unknown.
    let hasHeader =
      pmsetOutput.range(
        of: #"(?im)^System-wide power settings:\s*$"#,
        options: .regularExpression
      ) != nil
    let hasCurrentSettings =
      pmsetOutput.range(
        of: #"(?im)^Currently in use:\s*$"#,
        options: .regularExpression
      ) != nil
    let hasKnownPowerSetting =
      pmsetOutput.range(
        of: #"(?im)^\s*(sleep|displaysleep|ttyskeepawake)\s+\d+"#,
        options: .regularExpression
      ) != nil
    let containsMalformedSleepDisabled =
      pmsetOutput.range(
        of: #"(?im)^\s*SleepDisabled\b"#,
        options: .regularExpression
      ) != nil

    self =
      hasHeader && hasCurrentSettings && hasKnownPowerSetting && !containsMalformedSleepDisabled
      ? .normal
      : .unknown
  }

  init(helperOutput: String) {
    switch helperOutput.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "NORMAL": self = .normal
    case "AWAKE": self = .awake
    default: self = .unknown
    }
  }

  var helperOutput: String {
    switch self {
    case .normal: "NORMAL"
    case .awake: "AWAKE"
    case .unknown: "UNKNOWN"
    }
  }
}

enum DisplayState: Equatable {
  case normal
  case awake
  case executing
  case unknown
  case setupRequired
  case error(String)
}
