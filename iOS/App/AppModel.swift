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
  private var panelDoors: [Door] = Preferences.doors
  private(set) var customDoors: [Door] = Preferences.customDoors
  private(set) var hiddenDoorIDs: Set<Door.ID> = Preferences.hiddenDoorIDs
  private(set) var states: [Door.ID: DoorState] = [:]
  private(set) var isRefreshing = false
  var errorMessage: String?
  var dryRun: Bool = Preferences.dryRun {
    didSet { Preferences.dryRun = dryRun }
  }

  var isSignedIn: Bool { email != nil }

  var doors: [Door] { Preferences.merging(panelDoors, customDoors) }

  /// The doors shown on the door screen.
  var visibleDoors: [Door] { doors.filter { !hiddenDoorIDs.contains($0.id) } }

  func isHidden(_ door: Door) -> Bool {
    hiddenDoorIDs.contains(door.id)
  }

  func setHidden(_ door: Door, _ hidden: Bool) {
    if hidden { hiddenDoorIDs.insert(door.id) } else { hiddenDoorIDs.remove(door.id) }
    Preferences.hiddenDoorIDs = hiddenDoorIDs
  }

  /// Panel doors drop the shared 동 prefix; added doors keep their full name, since they're another 동.
  func title(for door: Door) -> String {
    customDoors.contains { $0.id == door.id } ? door.name : door.shortName
  }

  /// Adds an entrance the panel doesn't list. Returns false if it's already in the list.
  func addCustomDoor(_ door: Door) -> Bool {
    guard !doors.contains(where: { $0.id == door.id }) else { return false }
    customDoors.append(door)
    Preferences.customDoors = customDoors
    return true
  }

  func removeCustomDoor(_ door: Door) {
    customDoors.removeAll { $0.id == door.id }
    Preferences.customDoors = customDoors
    setHidden(door, false)
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
    panelDoors = []
    customDoors = []
    hiddenDoorIDs = []
    states = [:]
  }

  func warmUp() async {
    guard isSignedIn else { return }
    try? await client.ensureLoggedIn()
    if let fetched = try? await client.fetchDoors(), !fetched.isEmpty {
      panelDoors = fetched
      Preferences.doors = fetched
    }
  }

  func refreshDoors() async {
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      let fetched = try await client.fetchDoors()
      guard !fetched.isEmpty else {
        errorMessage = String(localized: "No entrances found on the lobby door panel.")
        return
      }
      panelDoors = fetched
      Preferences.doors = fetched
    } catch {
      errorMessage = error.localizedDescription
    }
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
