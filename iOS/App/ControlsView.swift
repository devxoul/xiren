import Observation
import SwiftUI

struct ControlsSnapshot: Sendable, Equatable {
  var lights: [SwitchDevice] = []
  var standby: [SwitchDevice] = []
  var heating: [Thermostat] = []
}

@MainActor
@Observable
final class ControlsModel {
  private(set) var snapshot = ControlsSnapshot()
  private(set) var busy: Set<String> = []
  private(set) var hasLoaded = false
  var message: String?
  private let client = EzvilleClient.shared
  private let fetch: @MainActor () async throws -> ControlsSnapshot
  private var refreshPending = false
  private var refreshing: Task<Void, Never>?

  var lights: [SwitchDevice] { snapshot.lights }
  var standby: [SwitchDevice] { snapshot.standby }
  var heating: [Thermostat] { snapshot.heating }

  init(fetch: (@MainActor () async throws -> ControlsSnapshot)? = nil) {
    self.fetch = fetch ?? {
      let client = EzvilleClient.shared
      return ControlsSnapshot(
        lights: try await client.fetchSwitches(.light),
        standby: try await client.fetchSwitches(.standby),
        heating: try await client.fetchThermostats()
      )
    }
  }

  func reload() async {
    await scheduleRefresh().value
  }

  /// Asks for a fetch that starts after this call. While one is running, another is queued, so a
  /// control that finishes mid-fetch still sees its result. Runs in its own Task so SwiftUI
  /// cancelling a view task can't cancel it halfway.
  func scheduleRefresh() -> Task<Void, Never> {
    refreshPending = true
    if let refreshing { return refreshing }
    let task = Task {
      while refreshPending {
        refreshPending = false
        do {
          snapshot = try await fetch()
        } catch {
          message = error.localizedDescription
        }
        hasLoaded = true
      }
      refreshing = nil
    }
    refreshing = task
    return task
  }

  func setSwitch(_ device: SwitchDevice, on: Bool) {
    run(device.id) { _ = try await $0.setSwitch(device, on: on) }
  }

  func setTemperature(_ thermostat: Thermostat, to temperature: Int) {
    run(thermostat.id) { _ = try await $0.setTemperature(thermostat, to: temperature) }
  }

  private func run(_ id: String, _ action: @escaping (EzvilleClient) async throws -> Void) {
    guard !busy.contains(id) else { return }
    busy.insert(id)
    Task {
      defer { busy.remove(id) }
      do {
        try await action(client)
        await scheduleRefresh().value
      } catch {
        message = error.localizedDescription
      }
    }
  }

}

struct ControlsView: View {
  @State private var model = ControlsModel()

  var body: some View {
    NavigationStack {
      List {
        switchSection("Lights", model.lights)
        heatingSection
        switchSection("Standby Power", model.standby)
      }
      .overlay {
        if !model.hasLoaded {
          ProgressView()
        } else if model.lights.isEmpty && model.standby.isEmpty && model.heating.isEmpty {
          ContentUnavailableView {
            Label("No Devices", systemImage: "lightbulb.slash")
          } description: {
            Text("Pull to refresh.")
          }
        }
      }
      .navigationTitle("Controls")
      .refreshable { await model.reload() }
      .task { if !model.hasLoaded { await model.reload() } }
      .alert("Controls", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(model.message ?? "")
      }
    }
  }

  @ViewBuilder private func switchSection(_ title: LocalizedStringKey, _ devices: [SwitchDevice]) -> some View {
    if !devices.isEmpty {
      Section(title) {
        ForEach(devices) { device in
          HStack {
            Toggle(name(of: device, in: devices), isOn: Binding(
              get: { device.isOn },
              set: { model.setSwitch(device, on: $0) }
            ))
            .disabled(model.busy.contains(device.id))
            if model.busy.contains(device.id) { ProgressView() }
          }
        }
      }
    }
  }

  @ViewBuilder private var heatingSection: some View {
    if !model.heating.isEmpty {
      Section {
        ForEach(model.heating) { thermostat in
          ThermostatRow(thermostat: thermostat, isBusy: model.busy.contains(thermostat.id)) {
            model.setTemperature(thermostat, to: $0)
          }
        }
      } header: {
        Text("Heating")
      } footer: {
        Text("Zones that are off can only be turned on at the wall pad.")
      }
    }
  }

  private func name(of device: SwitchDevice, in devices: [SwitchDevice]) -> String {
    let sameZone = devices.filter { $0.zone == device.zone }
    guard sameZone.count > 1, let index = sameZone.firstIndex(of: device) else { return device.zone }
    return "\(device.zone) \(index + 1)"
  }
}

private struct ThermostatRow: View {
  let thermostat: Thermostat
  let isBusy: Bool
  let apply: (Int) -> Void
  @State private var target: Int

  init(thermostat: Thermostat, isBusy: Bool, apply: @escaping (Int) -> Void) {
    self.thermostat = thermostat
    self.isBusy = isBusy
    self.apply = apply
    _target = State(initialValue: Self.initialTarget(thermostat))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(thermostat.zone).font(.headline)
        Spacer()
        Text(status).foregroundStyle(.secondary)
      }
      if thermostat.mode != .off {
        HStack {
          Stepper("\(target)°C", value: $target, in: Thermostat.temperatureRange)
          Button("Apply") { apply(target) }
            .buttonStyle(.bordered)
            .disabled(isBusy || !changed)
          if isBusy { ProgressView() }
        }
      }
    }
    .onChange(of: thermostat) { _, new in target = Self.initialTarget(new) }
  }

  private var changed: Bool {
    thermostat.mode == .away || target != Self.initialTarget(thermostat)
  }

  private var status: String {
    switch thermostat.mode {
    case .off: String(localized: "Off, now \(thermostat.current)°C")
    case .away: String(localized: "Away, now \(thermostat.current)°C")
    case .heating: String(localized: "\(thermostat.target)°C, now \(thermostat.current)°C")
    }
  }

  private static func initialTarget(_ thermostat: Thermostat) -> Int {
    let value = Int(Double(thermostat.target) ?? 0)
    return Thermostat.temperatureRange.contains(value) ? value : 22
  }
}
