import Foundation
import Observation

enum DoorState: Equatable {
  case idle
  case opening
  case success(String)
  case failure(String)
}

@MainActor
@Observable
final class AppModel {
  private let client = EzvilleClient.shared

  private(set) var email: String? = Keychain.loadCredentials()?.email
  private(set) var doors: [Door] = Preferences.doors
  private(set) var primaryDoorID: String? = Preferences.primaryDoorID
  private(set) var states: [Door.ID: DoorState] = [:]
  private(set) var isRefreshing = false
  var errorMessage: String?
  var dryRun: Bool = Preferences.dryRun {
    didSet { Preferences.dryRun = dryRun }
  }

  var isSignedIn: Bool { email != nil }

  var primaryDoor: Door? {
    doors.first { $0.id == primaryDoorID } ?? doors.first
  }

  var otherDoors: [Door] {
    doors.filter { $0.id != primaryDoor?.id }
  }

  func state(for door: Door) -> DoorState {
    states[door.id] ?? .idle
  }

  func signIn(email: String, password: String) async throws {
    try await client.login(email: email, password: password)
    Keychain.save(Credentials(email: email, password: password))
    self.email = email
    await refreshDoors()
  }

  func sendPasswordResetCode(_ form: PasswordResetForm) async throws -> String? {
    try await client.sendPasswordResetCode(form, dryRun: dryRun)
  }

  func verifyPasswordResetCode(_ form: PasswordResetForm) async throws -> String? {
    try await client.verifyPasswordResetCode(form, dryRun: dryRun)
  }

  func resetPassword(_ form: PasswordResetForm) async throws -> String? {
    try await client.resetPassword(form, dryRun: dryRun)
  }

  func signOut() async {
    await client.signOut()
    Keychain.deleteCredentials()
    Preferences.reset()
    email = nil
    doors = []
    primaryDoorID = nil
    states = [:]
  }

  func warmUp() async {
    guard isSignedIn else { return }
    try? await client.ensureLoggedIn()
    if let fetched = try? await client.fetchDoors(), !fetched.isEmpty {
      doors = fetched
      Preferences.doors = fetched
    }
  }

  func refreshDoors() async {
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      let fetched = try await client.fetchDoors()
      guard !fetched.isEmpty else {
        errorMessage = "No entrances found on the 공동현관 panel."
        return
      }
      doors = fetched
      Preferences.doors = fetched
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func setPrimary(_ door: Door) {
    primaryDoorID = door.id
    Preferences.primaryDoorID = door.id
  }

  func open(_ door: Door) async {
    guard state(for: door) != .opening else { return }
    states[door.id] = .opening
    do {
      states[door.id] = .success(try await client.openDoor(door, dryRun: dryRun))
    } catch {
      states[door.id] = .failure(error.localizedDescription)
    }
    let finished = states[door.id]
    try? await Task.sleep(for: .seconds(4))
    if states[door.id] == finished { states[door.id] = .idle }
  }
}
