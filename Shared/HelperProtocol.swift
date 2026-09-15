import Foundation

@objc protocol LidModePrivilegedProtocol {
  func status(withReply reply: @escaping (String, Int32) -> Void)
  func setDisableSleep(_ enabled: Bool, withReply reply: @escaping (String, Int32) -> Void)
}
