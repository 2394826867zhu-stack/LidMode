import Foundation
import os

enum AppLog {
  private static let subsystem = Bundle.main.bundleIdentifier ?? "app.lidmode"

  static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
  static let power = Logger(subsystem: subsystem, category: "power")
}
