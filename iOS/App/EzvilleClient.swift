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
      ("password_crypto", "2"), ("checkstring", checkstring),
    ])
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      throw EzvilleError.unexpectedResponse
    }
    guard EzvilleParser.isTruthy(json["result"]) else {
      throw EzvilleError.loginFailed(json["msg"] as? String ?? String(localized: "Login failed."))
    }
    // The web app lands on the home page after login, and the 조명/난방/대기전력스위치 panels answer
    // HTTP 500 until it has been loaded in the session.
    _ = try await get("/app/index.ifttt")
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

  /// Opens a 공동현관 door.
  func openDoor(_ door: Door) async throws -> String {
    guard EzvilleParser.isLobbyDoorCode(door.ho) else { throw EzvilleError.invalidDoor }
    let path = "/app/ctrl/openDoor.ifttt"
    return try await control(path, query: [("mode", "1"), ("dong", door.dong), ("ho", door.ho)])
  }

  // MARK: - Indoor controls

  private static let panelPath = "/app/ctrl/individualctrl.ifttt"

  func fetchSwitches(_ kind: SwitchKind) async throws -> [SwitchDevice] {
    try await fetchPanel(kind.panelType) { EzvilleParser.switches(in: $0, kind: kind) }
  }

  func fetchThermostats() async throws -> [Thermostat] {
    try await fetchPanel("난방") { EzvilleParser.thermostats(in: $0) }
  }

  /// Turns a light or standby outlet on or off.
  func setSwitch(_ device: SwitchDevice, on: Bool) async throws -> String {
    guard device.id.contains("_\(device.kind.rawValue)_") else { throw EzvilleError.unexpectedResponse }
    var query = [("id", device.id), ("power", on ? "on" : "off")]
    if device.kind == .standby { query.append(("state", "0")) }
    return try await control(device.kind.controlPath, query: query)
  }

  /// Sets a heating zone's target, as the panel's 온도적용 button does (`btnHeat()`, mode 1).
  func setTemperature(_ thermostat: Thermostat, to temperature: Int) async throws -> String {
    guard thermostat.id.contains("_heating_"), thermostat.mode != .off,
        Thermostat.temperatureRange.contains(temperature) else { throw EzvilleError.unexpectedResponse }
    let path = "/app/ctrl/individualctrlHeating.ifttt"
    let query = [
      ("id", thermostat.id), ("power", "on"), ("mode", "1"),
      ("curtemp", thermostat.current), ("settemp", "\(temperature).0"), ("_t", "0"),
    ]
    return try await control(path, query: query)
  }

  private func fetchPanel<T>(_ deviceType: String, parse: (String) -> [T]) async throws -> [T] {
    for _ in 0..<2 {
      try await ensureLoggedIn()
      let html = String(decoding: try await get(Self.panelPath, query: [("DEVICE_TYPE", deviceType)]), as: UTF8.self)
      let items = parse(html)
      if !items.isEmpty || !html.contains("loginView") { return items }
      loggedIn = false // bounced to the login page; retry once with a fresh session
    }
    return []
  }

  // MARK: - Visitors and recordings (read-only)

  private static let downloadMoviePath = "/app/ctrl/downloadMovie.ifttt"

  func fetchMedia(_ kind: MediaKind, page: Int) async throws -> MediaPage {
    for _ in 0..<2 {
      try await ensureLoggedIn()
      _ = try await get("/app/ctrl/individualctrl.ifttt", query: [("DEVICE_TYPE", kind.panelType)])
      if let result = EzvilleParser.mediaPage(try await get(kind.listPath, query: [("current_page", String(page))]), kind: kind) {
        return result
      }
      loggedIn = false // non-JSON body means the session expired
    }
    throw EzvilleError.unexpectedResponse
  }

  func imageData(_ image: MediaItem.Image) async throws -> Data {
    switch image {
    case .inline(let data):
      return data
    case .remote(let url):
      return try await send(URLRequest(url: url))
    case .proxied(let filename):
      try await ensureLoggedIn()
      return try await get(Self.downloadMoviePath, query: [("mode", "thumb"), ("filename", filename)])
    }
  }

  /// Downloads a recording to a temporary file, since AVPlayer can't send the session cookie itself.
  func movieFile(_ filename: String) async throws -> URL {
    try await ensureLoggedIn()
    let data = try await get(Self.downloadMoviePath, query: [("mode", "movie"), ("filename", filename)])
    guard !data.isEmpty else { throw EzvilleError.unexpectedResponse }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("recording.mp4")
    try data.write(to: file, options: .atomic)
    return file
  }

  // MARK: - Password reset (월패드 인증)

  private static let findPasswordPath = "/app/mypage/myPage_findPassword.ifttt"

  /// Asks the server to show a verification code on the household's wall pad. Starts a fresh
  /// session that the next steps reuse.
  func sendPasswordResetCode(_ form: PasswordResetForm) async throws {
    loggedIn = false
    clearCookies()
    _ = try await get(Self.findPasswordPath)
    try await expectResetCode(
      "/app/mypage/myPage_FindPassword_sendAuthNum.ifttt", form.query(),
      fallback: String(localized: "Couldn't send a code. Check the building, unit and email.")
    )
  }

  func verifyPasswordResetCode(_ form: PasswordResetForm) async throws {
    try await expectResetCode(
      "/app/mypage/myPage_FindPassword_checkAuthNum.ifttt", form.query(),
      fallback: String(localized: "Wrong or expired code.")
    )
  }

  func resetPassword(_ form: PasswordResetForm) async throws {
    let path = "/app/mypage/myPage_FindPassword_PWSave.ifttt"
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
    guard result.ok else { throw EzvilleError.server(result.message ?? String(localized: "Couldn't change the password.")) }
  }

  private func expectResetCode(_ path: String, _ query: [(String, String)], fallback: String) async throws {
    guard let result = EzvilleParser.resetCodeResult(try await get(path, query: query)) else {
      throw EzvilleError.unexpectedResponse
    }
    guard result.ok else { throw EzvilleError.server(result.message ?? fallback) }
  }

  private func control(_ path: String, query: [(String, String)]) async throws -> String {
    for _ in 0..<2 {
      try await ensureLoggedIn()
      let data = try await get(path, query: query)
      if let result = EzvilleParser.controlResult(data) {
        guard result.ok else { throw EzvilleError.server(result.message ?? String(localized: "Request failed.")) }
        return result.message ?? String(localized: "Done")
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
