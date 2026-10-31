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

/// Fields of the find-password page's `#theForm`, sent as query parameters by every step.
struct PasswordResetForm: Sendable {
  var dong = ""
  var ho = ""
  var email = ""
  var code = ""
  var newPassword = ""

  func query(includingPassword: Bool = false, seq: String = "", act: String = "auth") -> [(String, String)] {
    let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
    // Non-Android clients send the literal "token" (the page's own fallback).
    var query = [
      ("seq", seq), ("act", act), ("hh_dong", trim(dong)), ("hh_ho", trim(ho)),
      ("email", trim(email)), ("auth_num", trim(code)), ("devicetoken", "token"),
    ]
    if includingPassword { query += [("new_pwd", newPassword), ("new_pwd_check", newPassword)] }
    return query
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
    inputValue(id: "checkstring", in: html)
  }

  /// Value of `<input id="…" value="…">`, in either attribute order.
  static func inputValue(id: String, in html: String) -> String? {
    let id = NSRegularExpression.escapedPattern(for: id)
    return firstCapture(#"id\s*=\s*["']"# + id + #"["'][^>]*value\s*=\s*["']([^"']*)["']"#, in: html)
      ?? firstCapture(#"value\s*=\s*["']([^"']*)["'][^>]*id\s*=\s*["']"# + id + #"["']"#, in: html)
  }

  /// 영어 대문자/소문자/숫자/특수문자: 2 kinds need 10+ characters, 3+ kinds need 8+, at most 20.
  static func isAcceptedNewPassword(_ password: String) -> Bool {
    guard password.count <= 20 else { return false }
    let kinds = [
      password.contains { $0.isASCII && $0.isUppercase },
      password.contains { $0.isASCII && $0.isLowercase },
      password.contains { $0.isASCII && $0.isNumber },
      password.contains { !($0.isASCII && ($0.isLetter || $0.isNumber)) },
    ].filter { $0 }.count
    return (kinds >= 3 && password.count >= 8) || (kinds == 2 && password.count >= 10)
  }

  /// `sendAuthNum` / `checkAuthNum` succeed when `result == "0"` (the page's own check).
  static func resetCodeResult(_ data: Data) -> ControlResult? {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let value = json["result"] else { return nil }
    let ok = switch value {
    case let s as String: s == "0"
    case let n as NSNumber: n.intValue == 0
    default: false
    }
    return ControlResult(ok: ok, message: json["msg"] as? String)
  }

  /// `PWSave` is checked with JS truthiness (`if (res.result)`), so a non-empty string counts.
  static func passwordSaveResult(_ data: Data) -> ControlResult? {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let value = json["result"] else { return nil }
    let ok = switch value {
    case let s as String: !s.isEmpty
    case let n as NSNumber: n.intValue != 0
    default: false
    }
    return ControlResult(ok: ok, message: json["msg"] as? String)
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
