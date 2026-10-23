import Foundation
import AppIntents

/// Native Siri Voice Relay Intent for CarPlay & Hands-Free AG Project Consultation.
/// Uses Apple's native Siri microphone (`$question.requestValue`) and Siri's voice (`ProvidesDialog`)
/// so CarPlay's ceiling microphone and stereo ducking work with 100% reliability while consulting
/// all 56 of Dr. Mohit's Antigravity projects and archived threads on Cloudflare KV + Gemini 3.8 Flash.
@available(iOS 17.0, *)
struct StartCarSpeakIntent: AppIntent {
    static var title: LocalizedStringResource = "Consult CarSpeak on Antigravity Projects"
    static var description = IntentDescription("Hands-free voice consultation across all 56 Antigravity projects and archived threads using Siri voice on CarPlay.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Question or Antigravity Project",
        requestValueDialog: IntentDialog("CarSpeak ready. Which Antigravity project or topic would you like to discuss?")
    )
    var question: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let userQuery: String
        if let q = question?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            userQuery = q
        } else {
            userQuery = try await $question.requestValue(
                IntentDialog("CarSpeak ready. Which Antigravity project or question would you like to discuss?")
            )
        }

        let reply = await GeminiLiveSessionManager.shared.askSiriRelayQuestion(userQuery)

        // Offer a natural multi-turn follow-up loop right inside Siri on CarPlay
        if let followUp = try? await $question.requestValue(
            IntentDialog("\(reply) ... Anything else on this project, or say stop?")
        ) {
            let trimmedFollowUp = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmedFollowUp.lowercased()
            if !trimmedFollowUp.isEmpty,
               lower != "no",
               lower != "stop",
               lower != "nothing",
               lower != "that's all",
               lower != "thats all",
               lower != "cancel",
               lower != "done" {
                let secondReply = await GeminiLiveSessionManager.shared.askSiriRelayQuestion(trimmedFollowUp)
                return .result(dialog: IntentDialog(stringLiteral: secondReply))
            }
        }

        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

@available(iOS 17.0, *)
struct SwitchCarSpeakConversationIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch CarSpeak Conversation"
    static var description = IntentDescription("Switches CarSpeak to a previous archived conversation or Antigravity project thread.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Topic or Antigravity Project",
        requestValueDialog: IntentDialog("Which Antigravity project or archived conversation should CarSpeak switch to?")
    )
    var topic: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if let switched = await ConversationVaultClient.shared.switchConversation(queryOrId: topic) {
            let reply = await GeminiLiveSessionManager.shared.askSiriRelayQuestion(
                "We just switched to \(switched.title). In two concise sentences, summarize where we left off and ask what I want to tackle next."
            )
            return .result(dialog: IntentDialog(stringLiteral: reply))
        } else {
            let reply = await GeminiLiveSessionManager.shared.askSiriRelayQuestion(
                "Let's discuss my Antigravity project or topic: \(topic). Summarize its status in two sentences."
            )
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }
    }
}

@available(iOS 17.0, *)
struct CarSpeakShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCarSpeakIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
                "Open \(.applicationName) hands free",
                "Consult \(.applicationName)"
            ],
            shortTitle: "Ask CarSpeak",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: SwitchCarSpeakConversationIntent(),
            phrases: [
                "Switch \(.applicationName) conversation",
                "Resume project in \(.applicationName)"
            ],
            shortTitle: "Switch AG Project",
            systemImageName: "arrow.triangle.swap"
        )
    }
}
