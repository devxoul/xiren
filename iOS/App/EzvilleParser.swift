import CommonCrypto
import CryptoKit
import Foundation

struct Door: Codable, Hashable, Identifiable, Sendable {
  let dong: String
  let ho: String
  let name: String

  var id: String { "\(dong)-\(ho)" }

  /// Third digit of the 90FL code: 0 = 로비층, 1 = 지하 1층, 2 = 지하 2층 (as seen in 102동).
  var floor: Int { ((Int(ho) ?? 9000) - 9000) / 10 }

  /// Rows of doors sharing a 동 and floor, 동s in first-seen order, floors lobby first, codes ascending.
  static func floorRows(_ doors: [Door]) -> [[Door]] {
    var dongs: [String] = []
    for door in doors where !dongs.contains(door.dong) { dongs.append(door.dong) }
    return dongs.flatMap { dong in
      Dictionary(grouping: doors.filter { $0.dong == dong }, by: \.floor)
        .sorted { $0.key < $1.key }
        .map { $0.value.sorted { $0.ho < $1.ho } }
    }
  }

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

/// The two read-only media lists: 방문자 (door camera photos) and 방범영상 (recorded clips).
enum MediaKind: String, CaseIterable, Identifiable, Sendable {
  case visitors
  case recordings

  var id: Self { self }

  /// The list endpoints answer HTTP 500 until their panel has been opened in the session.
  var panelType: String {
    switch self {
    case .visitors: "방문자"
    case .recordings: "CCTV"
    }
  }

  var listPath: String {
    switch self {
    case .visitors: "/app/ctrl/getVisitorList.ifttt"
    case .recordings: "/app/ctrl/getCCTVList.ifttt"
    }
  }
}

/// One entry of `getVisitorList` / `getCCTVList`.
struct MediaItem: Hashable, Identifiable, Sendable {
  enum Image: Hashable, Sendable {
    /// JPEG bytes sent inline (`link == "base64"`).
    case inline(Data)
    /// An absolute image URL.
    case remote(URL)
    /// Fetched through `downloadMovie.ifttt?mode=thumb&filename=…`.
    case proxied(String)
  }

  let filename: String
  let location: String
  let image: Image?
  /// `filename` for `downloadMovie.ifttt?mode=movie`; nil for photos.
  let movie: String?

  var id: String { "\(location)/\(filename)" }

  /// The filename starts with the capture time, `yyyyMMddHHmmss`, in Korean time.
  var date: Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter.date(from: String(filename.prefix(14)))
  }
}

struct MediaPage: Sendable, Equatable {
  let items: [MediaItem]
  let totalPages: Int
}

/// On/off devices controlled the same way: 조명 and 대기전력스위치.
enum SwitchKind: String, CaseIterable, Sendable {
  case light
  case standby

  var panelType: String {
    switch self {
    case .light: "조명"
    case .standby: "대기전력스위치"
    }
  }

  var controlPath: String {
    switch self {
    case .light: "/app/ctrl/individualctrlLight.ifttt"
    case .standby: "/app/ctrl/individualctrlStandby.ifttt"
    }
  }
}

/// A light or standby-power outlet. `id` is `<home>_<dong>_<ho>_<kind>_<zone>_<index>`.
struct SwitchDevice: Hashable, Identifiable, Sendable {
  let kind: SwitchKind
  let id: String
  let zone: String
  let isOn: Bool
}

/// A heating zone. The app can only set the target while it's on; off is changed on the wall pad.
struct Thermostat: Hashable, Identifiable, Sendable {
  enum Mode: Hashable, Sendable {
    case off
    case away
    case heating
  }

  static let temperatureRange = 5...40

  let id: String
  let zone: String
  let current: String
  let target: String
  let mode: Mode
}

struct ControlResult: Sendable, Equatable {
  let ok: Bool
  let message: String?
}

enum EzvilleParser {
  /// Port of the login page's `pwEncode` (sent with `password_crypto=2`):
  /// `CryptoJS.AES.encrypt(password, checkstring).toString()`, i.e. OpenSSL-style
  /// base64("Salted__" + salt + AES-256-CBC ciphertext), key and IV from EVP_BytesToKey(MD5).
  static func encodePassword(
    _ password: String, checkstring: String,
    salt: [UInt8] = (0..<8).map { _ in UInt8.random(in: .min ... .max) }
  ) throws -> String {
    let passphrase = Array(checkstring.utf8)
    var derived: [UInt8] = []
    var block: [UInt8] = []
    while derived.count < 48 {
      block = Array(Insecure.MD5.hash(data: block + passphrase + salt))
      derived += block
    }
    let key = Array(derived[0..<32])
    let iv = Array(derived[32..<48])
    let plain = Array(password.utf8)
    var cipher = [UInt8](repeating: 0, count: plain.count + kCCBlockSizeAES128)
    var length = 0
    let status = CCCrypt(
      CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
      key, key.count, iv, plain, plain.count, &cipher, cipher.count, &length
    )
    guard status == kCCSuccess else { throw EzvilleError.passwordEncryptionFailed }
    return Data(Array("Salted__".utf8) + salt + cipher[0..<length]).base64EncodedString()
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

  /// A manually added entrance, such as another 동's 공동현관. Nil unless 동 is a number and 호 is a
  /// lobby door code. The name defaults to "<동>동 <호>".
  static func customDoor(dong: String, ho: String, name: String) -> Door? {
    let dong = dong.trimmingCharacters(in: .whitespacesAndNewlines)
    let ho = ho.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard Int(dong) != nil, isLobbyDoorCode(ho) else { return nil }
    return Door(dong: dong, ho: ho, name: name.isEmpty ? "\(dong)동 \(ho)" : name)
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

  /// Parses a `getVisitorList` / `getCCTVList` page. `result: false` means an empty list (its `msg` says
  /// so); nil means the body is not that JSON, usually a login page after the session expired.
  static func mediaPage(_ data: Data, kind: MediaKind) -> MediaPage? {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        json.keys.contains("result") else { return nil }
    guard isTruthy(json["result"]) else { return MediaPage(items: [], totalPages: 0) }
    let list = json["ctrlList"] as? [[String: Any]] ?? []
    let items = list.compactMap { entry -> MediaItem? in
      let string = { (key: String) in (entry[key] as? String) ?? "" }
      let filename = string("filename")
      guard !filename.isEmpty else { return nil }
      let data = string("data")
      let image: MediaItem.Image?
      let content = string("content")
      // Mirrors the panels' renderers: inline base64, else visitors show `data` as an image URL and
      // recordings pass `content` to `downloadMovie` for both the thumbnail and the clip.
      if string("link") == "base64" {
        image = Data(base64Encoded: data, options: .ignoreUnknownCharacters).map(MediaItem.Image.inline)
      } else if kind == .recordings {
        image = content.isEmpty ? nil : .proxied(content)
      } else {
        image = URL(string: data).map(MediaItem.Image.remote)
      }
      let movie = kind == .recordings && !content.isEmpty ? content : nil
      return MediaItem(filename: filename, location: string("location"), image: image, movie: movie)
    }
    let totalPages = (json["totalPage"] as? NSNumber)?.intValue ?? Int(json["totalPage"] as? String ?? "") ?? 1
    return MediaPage(items: items, totalPages: totalPages)
  }

  /// Reads the `zoneArray.push('…'); idArray.push('…'); …` blocks the control panels render, one
  /// record per `zoneArray.push`. Records without an id are skipped, as is a repeated id.
  static func panelRecords(in html: String) -> [[String: String]] {
    guard let regex = try? NSRegularExpression(pattern: #"(\w+)Array\.push\(\s*'([^']*)'\s*\)"#) else { return [] }
    let ns = html as NSString
    var records: [[String: String]] = []
    for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
      let key = ns.substring(with: match.range(at: 1))
      let value = ns.substring(with: match.range(at: 2))
      if key == "zone" { records.append([:]) }
      guard !records.isEmpty else { continue }
      records[records.count - 1][key] = value
    }
    var seen = Set<String>()
    return records.filter { record in
      guard let id = record["id"], !id.isEmpty else { return false }
      return seen.insert(id).inserted
    }
  }

  static func switches(in html: String, kind: SwitchKind) -> [SwitchDevice] {
    panelRecords(in: html).compactMap { record in
      guard let id = record["id"], id.contains("_\(kind.rawValue)_") else { return nil }
      return SwitchDevice(kind: kind, id: id, zone: record["zone"] ?? "", isOn: record["status"] == "on")
    }
  }

  /// Mirrors `heatingResult`: power off wins, then mode 0 is 외출, anything else is heating.
  static func thermostats(in html: String) -> [Thermostat] {
    panelRecords(in: html).compactMap { record in
      guard let id = record["id"], id.contains("_heating_") else { return nil }
      let mode: Thermostat.Mode = record["power"] == "off" ? .off : record["mode"] == "0" ? .away : .heating
      return Thermostat(id: id, zone: record["zone"] ?? "", current: record["currentTemp"] ?? "",
                        target: record["setTemp"] ?? "", mode: mode)
    }
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
  case passwordEncryptionFailed
  case loginFailed(String)
  case http(Int)
  case invalidDoor
  case server(String)
  case unexpectedResponse
  case unplayableVideo

  var errorDescription: String? {
    switch self {
    case .missingCredentials: String(localized: "Not signed in.")
    case .checkstringNotFound: String(localized: "Login page changed (checkstring not found).")
    case .passwordEncryptionFailed: String(localized: "Couldn't encrypt the password.")
    case .loginFailed(let msg): msg
    case .http(let code): String(localized: "Server error (HTTP \(code)).")
    case .invalidDoor: String(localized: "Not a lobby door code.")
    case .server(let msg): msg
    case .unexpectedResponse: String(localized: "Unexpected response from server.")
    case .unplayableVideo: String(localized: "The video can't be played.")
    }
  }
}
