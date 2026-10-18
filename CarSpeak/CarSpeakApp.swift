import SwiftUI

@main
struct CarSpeakApp: App {
    init() {
        SteeringWheelController.shared.configureRemoteCommands()
    }

    var body: some Scene {
        WindowGroup {
            CockpitView()
                .preferredColorScheme(.light)
        }
    }
}
