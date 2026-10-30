import SwiftUI

@main
struct CarSpeakApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
