import SwiftUI

struct DoorsView: View {
  @Environment(AppModel.self) private var model
  @State private var showSettings = false

  var body: some View {
    @Bindable var model = model
    NavigationStack {
      ScrollView {
        VStack(spacing: 12) {
          if model.dryRun {
            Label("Dry run: doors will not actually open", systemImage: "testtube.2")
              .font(.footnote.weight(.medium))
              .foregroundStyle(.orange)
              .frame(maxWidth: .infinity)
              .padding(10)
              .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12))
          }

          if let primary = model.primaryDoor {
            DoorButton(door: primary, state: model.state(for: primary), prominent: true) {
              Task { await model.open(primary) }
            }
          }

          LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(model.otherDoors) { door in
              DoorButton(door: door, state: model.state(for: door), prominent: false) {
                Task { await model.open(door) }
              }
              .contextMenu {
                Button("Make Primary", systemImage: "star") { model.setPrimary(door) }
              }
            }
          }

          if model.doors.isEmpty {
            ContentUnavailableView {
              Label("No Entrances", systemImage: "door.left.hand.closed")
            } description: {
              Text("Pull to load entrances from the 공동현관 panel.")
            } actions: {
              Button("Load") { Task { await model.refreshDoors() } }
                .disabled(model.isRefreshing)
            }
          }
        }
        .padding()
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("공동현관")
      .refreshable { await model.refreshDoors() }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
      }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(model.errorMessage ?? "")
      }
    }
  }
}

struct DoorButton: View {
  let door: Door
  let state: DoorState
  let prominent: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: prominent ? 12 : 8) {
        HStack {
          icon
          Spacer()
          if prominent {
            Image(systemName: "star.fill").font(.caption).opacity(0.7)
          }
        }
        Spacer(minLength: 0)
        Text(door.shortName)
          .font(prominent ? .title2.bold() : .headline)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
        Text(statusText)
          .font(.caption)
          .lineLimit(2)
          .opacity(0.8)
      }
      .frame(maxWidth: .infinity, minHeight: prominent ? 180 : 120, alignment: .leading)
      .padding(prominent ? 20 : 14)
      .foregroundStyle(foreground)
      .background(background, in: .rect(cornerRadius: prominent ? 28 : 20))
      .contentShape(.rect(cornerRadius: prominent ? 28 : 20))
    }
    .buttonStyle(PressableStyle())
    .disabled(state == .opening)
    .sensoryFeedback(trigger: state) { _, new in
      switch new {
      case .opening: .impact(weight: .medium)
      case .success: .success
      case .failure: .error
      case .idle: nil
      }
    }
    .animation(.snappy, value: state)
  }

  @ViewBuilder private var icon: some View {
    switch state {
    case .opening: ProgressView().tint(foreground)
    case .success: Image(systemName: "door.left.hand.open").font(prominent ? .title : .title3)
    case .failure: Image(systemName: "exclamationmark.triangle.fill").font(prominent ? .title : .title3)
    case .idle: Image(systemName: "door.left.hand.closed").font(prominent ? .title : .title3)
    }
  }

  private var statusText: String {
    switch state {
    case .idle: "Tap to open"
    case .opening: "Opening..."
    case .success(let msg): msg
    case .failure(let msg): msg
    }
  }

  private var background: Color {
    switch state {
    case .success: .green
    case .failure: .red
    case .idle, .opening: prominent ? .accentColor : Color(.secondarySystemGroupedBackground)
    }
  }

  private var foreground: Color {
    switch state {
    case .success, .failure: .white
    case .idle, .opening: prominent ? .white : .primary
    }
  }
}

private struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.snappy(duration: 0.15), value: configuration.isPressed)
  }
}
