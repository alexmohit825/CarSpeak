import SwiftUI

@main
struct CarSpeakApp: App {
    init() {
        SteeringWheelController.shared.configureRemoteCommands()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                CockpitView()
                    .tabItem {
                        Label("Cockpit", systemImage: "waveform.circle.fill")
                    }

                ArchiveListView()
                    .tabItem {
                        Label("Archived Threads", systemImage: "tray.full.fill")
                    }

                AGProjectsPortfolioView()
                    .tabItem {
                        Label("AG Projects", systemImage: "square.stack.3d.up.fill")
                    }
            }
            .preferredColorScheme(.dark)
        }
    }
}
