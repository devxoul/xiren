import Foundation

struct Door: Codable, Hashable, Identifiable, Sendable {
  let dong: String
  let ho: String
  let name: String

  var id: String { "\(dong)-\(ho)" }

  /// "101동 로비층 1~2라인" -> "로비층 1~2라인"
  var shortName: String {
    let trimmed = name.replacingOccurrences(of: #"^\s*\d+동\s*"#, with: "", options: .regularExpression)
    return trimmed.isEmpty ? name : trimmed
  }
}

struct ControlResult: Sendable, Equatable {
  let ok: Bool
  let message: String?
}

enum EzvilleParser {
  /// Port of `pwEncode` from `/asset/js/common.js`: byte-wise XOR of the password with the
  /// per-session `checkstring`, padded with 0 past the password's end, upper-case hex.
  static func encodePassword(_ password: String, checkstring: String) throws -> String {
    let p = Array(password.utf16)
    let c = Array(checkstring.utf16)
    guard !c.isEmpty, p.count <= c.count else { throw EzvilleError.passwordTooLong }
    return c.indices.map { i in
      String(format: "%02X", (i < p.count ? p[i] : 0) ^ c[i])
    }.joined()
  }

  static func checkstring(in html: String) -> String? {
    firstCapture(#"id\s*=\s*["']checkstring["'][^>]*value\s*=\s*["']([^"']*)["']"#, in: html)
      ?? firstCapture(#"value\s*=\s*["']([^"']*)["'][^>]*id\s*=\s*["']checkstring["']"#, in: html)
  }

  /// 공동현관 entrances are encoded as pseudo unit numbers in the 9000 range (`btnOpen()` guard).
  static func isLobbyDoorCode(_ ho: String) -> Bool {
    guard let n = Int(ho) else { return false }
    return n / 9000 == 1
  }

  /// Parses `<li onclick="selectDoor(idx, dong, ho, 'lobby')">label</li>` entries from the
  /// `DEVICE_TYPE=로비문열림` panel.
  static func doors(in html: String) -> [Door] {
    let pattern = #"<li\b[^>]*selectDoor\(([^)]*)\)[^>]*>(.*?)</li>"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
    let ns = html as NSString
    var seen = Set<String>()
    var result: [Door] = []
    for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
      let args = ns.substring(with: match.range(at: 1))
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r'\"")) }
      guard args.count >= 3 else { continue }
      let dong = args[1], ho = args[2]
      guard Int(dong) != nil, isLobbyDoorCode(ho) else { continue }
      let label = entranceLabel(plainText(ns.substring(with: match.range(at: 2))))
      let door = Door(dong: dong, ho: ho, name: label.isEmpty ? "\(dong)동 \(ho)" : label)
      if seen.insert(door.id).inserted { result.append(door) }
    }
    return result
  }

  /// Each panel row also renders the door kind tag and the 선택 button, e.g. "101동 로비층 1~2라인 (lobby) 선택".
  static func entranceLabel(_ text: String) -> String {
    text
      .replacingOccurrences(of: #"\([A-Za-z]+\)"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s*선택\s*$"#, with: "", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Control endpoints answer `{result, msg}`. Returns nil when the body is not that JSON
  /// (typically an HTML login page after the session expired).
  static func controlResult(_ data: Data) -> ControlResult? {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        json.keys.contains("result") else { return nil }
    return ControlResult(ok: isTruthy(json["result"]), message: json["msg"] as? String)
  }

  static func isTruthy(_ value: Any?) -> Bool {
    switch value {
    case let b as Bool: return b
    case let n as NSNumber: return n.intValue != 0
    case let s as String: return ["1", "true", "y", "ok", "success"].contains(s.lowercased())
    default: return false
    }
  }

  private static func plainText(_ html: String) -> String {
    var s = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    for (entity, char) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&#126;": "~"] {
      s = s.replacingOccurrences(of: entity, with: char)
    }
    return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func firstCapture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
  }
}

enum EzvilleError: LocalizedError {
  case missingCredentials
  case checkstringNotFound
  case passwordTooLong
  case loginFailed(String)
  case http(Int)
  case invalidDoor
  case server(String)
  case unexpectedResponse

  var errorDescription: String? {
    switch self {
    case .missingCredentials: "Not signed in."
    case .checkstringNotFound: "Login page changed (checkstring not found)."
    case .passwordTooLong: "Password is longer than the login checkstring."
    case .loginFailed(let msg): msg
    case .http(let code): "Server error (HTTP \(code))."
    case .invalidDoor: "Not a lobby door code."
    case .server(let msg): msg
    case .unexpectedResponse: "Unexpected response from server."
    }
  }
}
