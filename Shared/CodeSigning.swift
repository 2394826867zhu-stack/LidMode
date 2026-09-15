import Foundation
import Security

enum CodeSigning {
  static func currentTeamIdentifier() -> String? {
    var dynamicCode: SecCode?
    guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess, let dynamicCode else {
      return nil
    }

    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess, let staticCode
    else {
      return nil
    }

    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard
      SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
      let values = information as? [String: Any]
    else {
      return nil
    }

    return values[kSecCodeInfoTeamIdentifier as String] as? String
  }

  static func sameTeamRequirement(identifier: String) -> String? {
    guard let teamIdentifier = currentTeamIdentifier() else { return nil }
    return
      "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
  }
}
