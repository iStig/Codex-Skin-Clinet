import SwiftUI

@main
struct DreamSkinControlApp: App {
  @StateObject private var model = DreamSkinModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .frame(minWidth: 820, minHeight: 560)
    }
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .newItem) { }
      CommandGroup(after: .appInfo) {
        Button(L10n.text("Refresh Status")) { Task { await model.refresh() } }
          .keyboardShortcut("r", modifiers: .command)
      }
    }
  }
}
