import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var showAddDoor = false

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Section {
          Toggle("Dry Run", isOn: $model.dryRun)
        } footer: {
          Text("When on, tapping a door only shows the request that would be sent. Turn off to actually open doors.")
        }

        Section {
          Button("Reload Entrances") { Task { await model.refreshDoors() } }
            .disabled(model.isRefreshing)
        }

        Section {
          ForEach(model.customDoors) { door in
            VStack(alignment: .leading) {
              Text(door.name)
              Text("\(door.dong)동 \(door.ho)").font(.caption).foregroundStyle(.secondary)
            }
          }
          .onDelete { offsets in
            offsets.map { model.customDoors[$0] }.forEach(model.removeCustomDoor)
          }
          Button("Add Entrance", systemImage: "plus") { showAddDoor = true }
        } header: {
          Text("Other Entrances")
        } footer: {
          Text("Add a 공동현관 the panel doesn't list, such as another 동's. The server may refuse doors outside your own 동.")
        }

        Section {
          Text("Use the Shortcuts app, Siri, or the Action Button with “Open Entrance” for one-press access.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Section {
          LabeledContent("Account", value: model.email ?? "-")
          Button("Sign Out", role: .destructive) {
            Task {
              await model.signOut()
              dismiss()
            }
          }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .sheet(isPresented: $showAddDoor) { AddDoorView() }
    }
  }
}

private struct AddDoorView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var dong = ""
  @State private var ho = ""
  @State private var name = ""
  @State private var error: String?

  private var door: Door? { EzvilleParser.customDoor(dong: dong, ho: ho, name: name) }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("동 (e.g. 101)", text: $dong).keyboardType(.numberPad)
          TextField("Entrance code (e.g. 9001)", text: $ho).keyboardType(.numberPad)
          TextField("Name (optional)", text: $name)
        } footer: {
          if let error {
            Text(error).foregroundStyle(.red)
          } else {
            Text("Entrance codes are in the 9000 range: 90x1 for lines 1~2, 90x3 for lines 3~4, with x = 0 for the lobby, 1 for B1 and 2 for B2 in 102동. Other 동s may differ.")
          }
        }
      }
      .navigationTitle("Add Entrance")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            guard let door else { return }
            if model.addCustomDoor(door) { dismiss() } else { error = "This entrance is already in the list." }
          }
          .disabled(door == nil)
        }
      }
    }
  }
}
