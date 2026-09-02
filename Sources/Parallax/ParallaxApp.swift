import SwiftUI

@main
struct ParallaxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(ParallaxTheme.bg)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
