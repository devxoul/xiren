import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Section {
          Toggle("Dry Run", isOn: $model.dryRun)
        } footer: {
          Text("When on, tapping a door only shows the request that would be sent. Turn off to actually open doors.")
        }

        Section("Primary Entrance") {
          Picker("Primary", selection: Binding(
            get: { model.primaryDoor?.id ?? "" },
            set: { id in if let door = model.doors.first(where: { $0.id == id }) { model.setPrimary(door) } }
          )) {
            ForEach(model.doors) { Text($0.name).tag($0.id) }
          }
          .pickerStyle(.inline)
          .labelsHidden()
          Button("Reload Entrances") { Task { await model.refreshDoors() } }
            .disabled(model.isRefreshing)
        }

        Section {
          Text("Use the Shortcuts app, Siri, or the Action Button with “Open Primary Door” for one-press access.")
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
    }
  }
}
