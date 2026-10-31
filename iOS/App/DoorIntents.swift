import AppIntents

struct DoorEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Entrance"
  static let defaultQuery = DoorQuery()

  let id: String
  let name: String

  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

  init(_ door: Door) {
    id = door.id
    name = door.name
  }
}

struct DoorQuery: EntityQuery {
  func entities(for identifiers: [DoorEntity.ID]) async throws -> [DoorEntity] {
    Preferences.allDoors.filter { identifiers.contains($0.id) }.map(DoorEntity.init)
  }

  func suggestedEntities() async throws -> [DoorEntity] {
    Preferences.allDoors.map(DoorEntity.init)
  }
}

struct OpenDoorIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Entrance"
  static let description = IntentDescription("Opens a 공동현관 entrance door.")

  @Parameter(title: "Entrance")
  var door: DoorEntity

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let target = Preferences.allDoors.first(where: { $0.id == door.id }) else { throw EzvilleError.invalidDoor }
    let message = try await EzvilleClient.shared.openDoor(target, dryRun: Preferences.dryRun)
    return .result(dialog: "\(message)")
  }
}

struct OpenPrimaryDoorIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Primary Door"
  static let description = IntentDescription("Opens your primary 공동현관 entrance.")

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let doors = Preferences.allDoors
    guard let target = doors.first(where: { $0.id == Preferences.primaryDoorID }) ?? doors.first else {
      throw EzvilleError.invalidDoor
    }
    let message = try await EzvilleClient.shared.openDoor(target, dryRun: Preferences.dryRun)
    return .result(dialog: "\(target.shortName): \(message)")
  }
}

struct XirenShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenPrimaryDoorIntent(),
      phrases: ["Open the door with \(.applicationName)", "\(.applicationName) open door"],
      shortTitle: "Open Primary Door",
      systemImageName: "door.left.hand.open"
    )
    AppShortcut(
      intent: OpenDoorIntent(),
      phrases: ["Open an entrance with \(.applicationName)"],
      shortTitle: "Open Entrance",
      systemImageName: "door.left.hand.closed"
    )
  }
}
