import Foundation

actor EzvilleClient {
  static let shared = EzvilleClient()

  static let baseURL = URL(string: "https://smartmobile1.ezville.net")!
  private static let appVersion = "2.6.4"
  // The web app keys behavior off "android " (lowercase + space) in the UA.
  private static let userAgent = "Mozilla/5.0 (Linux; Android 14; Pixel 8; wv) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36"

  private let session: URLSession
  private var loggedIn = false
  private var loginTask: Task<Void, Error>?

  init() {
    let config = URLSessionConfiguration.default
    config.httpCookieStorage = .shared
    config.httpCookieAcceptPolicy = .always
    config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
    config.timeoutIntervalForRequest = 10
    session = URLSession(configuration: config)
  }

  func login(email: String, password: String) async throws {
    loggedIn = false
    try await performLogin(email: email, password: password)
  }

  func ensureLoggedIn() async throws {
    if loggedIn { return }
    if let loginTask { return try await loginTask.value }
    guard let credentials = Keychain.loadCredentials() else { throw EzvilleError.missingCredentials }
    let task = Task { try await self.performLogin(email: credentials.email, password: credentials.password) }
    loginTask = task
    defer { loginTask = nil }
    try await task.value
  }

  func signOut() {
    loggedIn = false
    clearCookies()
  }

  private func performLogin(email: String, password: String) async throws {
    clearCookies()
    _ = try await get("/")
    _ = try await get("/app/check_auth_main.ifttt", query: [("email", email), ("version", Self.appVersion)])
    let html = String(decoding: try await get("/app/login/loginView.ifttt"), as: UTF8.self)
    guard let checkstring = EzvilleParser.checkstring(in: html) else { throw EzvilleError.checkstringNotFound }
    let encoded = try EzvilleParser.encodePassword(password, checkstring: checkstring)
    let data = try await post("/app/login/loginProc.ifttt", form: [
      ("mode", "0"), ("version", Self.appVersion), ("userid", email), ("passwd", ""),
      ("autologinYN", "N"), ("devicekind", "android"), ("provisionYN", "null"),
      ("deviceToken", encoded), ("accessToken", ""), ("captchaText", ""),
      ("password_crypto", "0"), ("checkstring", checkstring),
    ])
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      throw EzvilleError.unexpectedResponse
    }
    guard EzvilleParser.isTruthy(json["result"]) else {
      throw EzvilleError.loginFailed(json["msg"] as? String ?? "Login failed.")
    }
    loggedIn = true
  }

  func fetchDoors() async throws -> [Door] {
    for _ in 0..<2 {
      try await ensureLoggedIn()
      let html = String(decoding: try await get("/app/ctrl/individualctrl.ifttt", query: [("DEVICE_TYPE", "로비문열림")]), as: UTF8.self)
      let doors = EzvilleParser.doors(in: html)
      if !doors.isEmpty { return doors }
      loggedIn = false // probably bounced to a login page; retry once with a fresh session
    }
    return []
  }

  /// Opens a 공동현관 door. With `dryRun` the request is only described, never sent.
  func openDoor(_ door: Door, dryRun: Bool) async throws -> String {
    guard EzvilleParser.isLobbyDoorCode(door.ho) else { throw EzvilleError.invalidDoor }
    let path = "/app/ctrl/openDoor.ifttt"
    let query = [("mode", "1"), ("dong", door.dong), ("ho", door.ho)]
    if dryRun {
      return "Dry run: GET \(makeURL(path, query: query).relativePath)?\(Self.encode(query))"
    }
    return try await control(path, query: query)
  }

  // MARK: - Password reset (월패드 인증)

  private static let findPasswordPath = "/app/mypage/myPage_findPassword.ifttt"

  /// Asks the server to show a verification code on the household's wall pad. Starts a fresh
  /// session that the next steps reuse. Returns the request description in dry run, nil once sent.
  func sendPasswordResetCode(_ form: PasswordResetForm, dryRun: Bool) async throws -> String? {
    let path = "/app/mypage/myPage_FindPassword_sendAuthNum.ifttt"
    let query = form.query()
    if dryRun { return Self.describe(path, query) }
    loggedIn = false
    clearCookies()
    _ = try await get(Self.findPasswordPath)
    try await expectResetCode(path, query, fallback: "Couldn't send a code. Check the 동, 호 and email.")
    return nil
  }

  func verifyPasswordResetCode(_ form: PasswordResetForm, dryRun: Bool) async throws -> String? {
    let path = "/app/mypage/myPage_FindPassword_checkAuthNum.ifttt"
    let query = form.query()
    if dryRun { return Self.describe(path, query) }
    try await expectResetCode(path, query, fallback: "Wrong or expired code.")
    return nil
  }

  func resetPassword(_ form: PasswordResetForm, dryRun: Bool) async throws -> String? {
    let path = "/app/mypage/myPage_FindPassword_PWSave.ifttt"
    if dryRun { return Self.describe(path, form.query(includingPassword: true)) }
    // The web page reloads after verification; pick up the hidden fields it renders then.
    let html = String(decoding: try await get(Self.findPasswordPath), as: UTF8.self)
    let query = form.query(
      includingPassword: true,
      seq: EzvilleParser.inputValue(id: "seq", in: html) ?? "",
      act: EzvilleParser.inputValue(id: "act", in: html) ?? "auth"
    )
    guard let result = EzvilleParser.passwordSaveResult(try await get(path, query: query)) else {
      throw EzvilleError.unexpectedResponse
    }
    guard result.ok else { throw EzvilleError.server(result.message ?? "Couldn't change the password.") }
    return nil
  }

  private func expectResetCode(_ path: String, _ query: [(String, String)], fallback: String) async throws {
    guard let result = EzvilleParser.resetCodeResult(try await get(path, query: query)) else {
      throw EzvilleError.unexpectedResponse
    }
    guard result.ok else { throw EzvilleError.server(result.message ?? fallback) }
  }

  private static func describe(_ path: String, _ query: [(String, String)]) -> String {
    let masked = query.map { key, value in (key, key.hasPrefix("new_pwd") ? "***" : value) }
    return "Dry run: GET \(path)?\(encode(masked))"
  }

  private func control(_ path: String, query: [(String, String)]) async throws -> String {
    for _ in 0..<2 {
      try await ensureLoggedIn()
      let data = try await get(path, query: query)
      if let result = EzvilleParser.controlResult(data) {
        guard result.ok else { throw EzvilleError.server(result.message ?? "Request failed.") }
        return result.message ?? "Done"
      }
      loggedIn = false // non-JSON body means the session expired
    }
    throw EzvilleError.unexpectedResponse
  }

  private func get(_ path: String, query: [(String, String)] = []) async throws -> Data {
    try await send(URLRequest(url: makeURL(path, query: query)))
  }

  private func post(_ path: String, form: [(String, String)]) async throws -> Data {
    var request = URLRequest(url: makeURL(path, query: []))
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(Self.encode(form).utf8)
    return try await send(request)
  }

  private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      throw EzvilleError.http(http.statusCode)
    }
    return data
  }

  private func makeURL(_ path: String, query: [(String, String)]) -> URL {
    var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    if !query.isEmpty { components.percentEncodedQuery = Self.encode(query) }
    return components.url!
  }

  private static func encode(_ pairs: [(String, String)]) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return pairs.map { key, value in
      "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
    }.joined(separator: "&")
  }

  private func clearCookies() {
    let storage = HTTPCookieStorage.shared
    for cookie in storage.cookies(for: Self.baseURL) ?? [] { storage.deleteCookie(cookie) }
  }
}
