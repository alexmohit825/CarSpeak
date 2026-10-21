import Foundation
import AppIntents

@available(iOS 17.0, *)
struct StartCarSpeakIntent: AudioStartingIntent {
    static var title: LocalizedStringResource = "Start CarSpeak Hands-Free Session"
    static var description = IntentDescription("Launches CarSpeak directly into hands-free cabin audio mode.")
    /// CRITICAL FOR CARPLAY: Must be false so Siri does not attempt to foreground the locked device UIWindowScene
    /// (which times out after ~7 seconds while driving and causes Siri to say "Something went wrong. Please try again").
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        SteeringWheelController.shared.configureRemoteCommands()
        // Allow Siri's audio session to dismiss cleanly (350ms), then immediately start CarSpeak cabin audio
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            GeminiLiveSessionManager.shared.restartOrStartHandsFreeSession()
        }
        return .result()
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
    func perform() async throws -> some IntentResult {
        SteeringWheelController.shared.configureRemoteCommands()
        let targetTopic = topic
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Task { @MainActor in
                if !GeminiLiveSessionManager.shared.isLiveSessionActive {
                    GeminiLiveSessionManager.shared.restartOrStartHandsFreeSession()
                } else {
                    GeminiLiveSessionManager.shared.audioEngine.ensureEngineRunning()
                }
                if let switched = await ConversationVaultClient.shared.switchConversation(queryOrId: targetTopic) {
                    SteeringWheelController.shared.updateNowPlayingDashboard()
                    await GeminiLiveSessionManager.shared.sendVoiceOrTextCommand("We switched to \(switched.title). Briefly summarize where we left off.")
                } else {
                    await GeminiLiveSessionManager.shared.sendVoiceOrTextCommand("Switch to our conversation on \(targetTopic)")
                }
            }
        }
        return .result()
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
