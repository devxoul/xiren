import SwiftUI

@main
struct XirenApp: App {
  @State private var model = AppModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      Group {
        if model.isSignedIn {
          DoorsView()
        } else {
          LoginView()
        }
      }
      .environment(model)
    }
    .onChange(of: scenePhase, initial: true) { _, phase in
      if phase == .active { Task { await model.warmUp() } }
    }
  }
}
