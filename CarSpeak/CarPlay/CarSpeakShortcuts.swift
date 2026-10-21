import Foundation
import AppIntents

@available(iOS 17.0, *)
struct StartCarSpeakIntent: AudioStartingIntent {
    static var title: LocalizedStringResource = "Start CarSpeak Hands-Free Session"
    static var description = IntentDescription("Launches CarSpeak directly into hands-free cabin audio mode.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SteeringWheelController.shared.configureRemoteCommands()
        GeminiLiveSessionManager.shared.startOrResumeFromSiriOrCarPlay()
        return .result(dialog: "CarSpeak listening.")
    }
}

@available(iOS 17.0, *)
struct SwitchCarSpeakConversationIntent: AudioStartingIntent {
    static var title: LocalizedStringResource = "Switch CarSpeak Conversation"
    static var description = IntentDescription("Switches CarSpeak to a previous archived conversation or Antigravity project thread.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Topic or Antigravity Project")
    var topic: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SteeringWheelController.shared.configureRemoteCommands()
        let targetTopic = topic
        GeminiLiveSessionManager.shared.startOrResumeFromSiriOrCarPlay(switchTopic: targetTopic)
        return .result(dialog: "Switching CarSpeak.")
    }
}

@available(iOS 17.0, *)
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
