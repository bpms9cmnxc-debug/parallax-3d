import SwiftUI

@main
struct ParallaxTrackApp: App {
    var body: some Scene {
        WindowGroup {
            TrackView()
                .preferredColorScheme(.dark)
        }
    }
}
