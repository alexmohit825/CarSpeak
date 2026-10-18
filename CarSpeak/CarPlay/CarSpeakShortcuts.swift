import Foundation
import AppIntents

@available(iOS 16.0, *)
struct StartCarSpeakIntent: AppIntent {
    static var title: LocalizedStringResource = "Start CarSpeak Hands-Free Session"
    static var description = IntentDescription("Launches CarSpeak directly into full-duplex CarPlay cabin audio mode.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SteeringWheelController.shared.configureRemoteCommands()
        GeminiLiveSessionManager.shared.startHandsFreeSession()
        let activeTitle = ConversationVaultClient.shared.activeConversation?.title ?? "your active thread"
        return .result(dialog: "CarSpeak is live on CarPlay. Resuming \(activeTitle).")
    }
}

@available(iOS 16.0, *)
struct SwitchCarSpeakConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch CarSpeak Conversation"
    static var description = IntentDescription("Switches CarSpeak to a previous archived conversation or Antigravity project thread.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Topic or Antigravity Project")
    var topic: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SteeringWheelController.shared.configureRemoteCommands()
        if !GeminiLiveSessionManager.shared.isLiveSessionActive {
            GeminiLiveSessionManager.shared.startHandsFreeSession()
        }
        if let switched = await ConversationVaultClient.shared.switchConversation(queryOrId: topic) {
            SteeringWheelController.shared.updateNowPlayingDashboard()
            return .result(dialog: "Switched CarSpeak to \(switched.title). \(switched.summary)")
        }
        await GeminiLiveSessionManager.shared.sendVoiceOrTextCommand("Switch to our conversation on \(topic)")
        return .result(dialog: "Switched CarSpeak to \(topic).")
    }
}

@available(iOS 16.0, *)
struct CarSpeakShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCarSpeakIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Open \(.applicationName) hands free",
                "Talk to \(.applicationName)",
                "Resume \(.applicationName) on CarPlay"
            ],
            shortTitle: "Start CarSpeak",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: SwitchCarSpeakConversationIntent(),
            phrases: [
                "Switch \(.applicationName) conversation",
                "Resume project in \(.applicationName)"
            ],
            shortTitle: "Switch Conversation",
            systemImageName: "arrow.triangle.swap"
        )
    }
}
