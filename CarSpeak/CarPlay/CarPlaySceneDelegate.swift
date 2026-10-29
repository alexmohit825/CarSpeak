import Foundation
import CarPlay
import UIKit
import Combine

/// MS Copilot-Style CarPlay Dashboard Scene Delegate.
/// Tapping the CarSpeak icon on the CarPlay dashboard immediately starts the continuous
/// turn-by-turn hands-free conversation loop (Greeting -> Listen -> Answer -> Auto-Listen)
/// WITHOUT ever invoking Siri!
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        SteeringWheelController.shared.configureRemoteCommands()

        let rootTemplate = buildCarPlayRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)

        // Automatically start the continuous MS Copilot-style voice loop upon CarPlay launch
        GeminiLiveSessionManager.shared.startOrResumeFromSiriOrCarPlay()

        // Refresh CarPlay screen whenever active conversation or live transcript updates
        ConversationVaultClient.shared.$conversations
            .combineLatest(
                ConversationVaultClient.shared.$agProjects,
                GeminiLiveSessionManager.shared.$connectionStatusText
            )
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _ in
                guard let self = self, let ic = self.interfaceController else { return }
                let updatedRoot = self.buildCarPlayRootTemplate()
                ic.setRootTemplate(updatedRoot, animated: false, completion: nil)
            }
            .store(in: &cancellables)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        SteeringWheelController.shared.configureRemoteCommands()
        GeminiLiveSessionManager.shared.startOrResumeFromSiriOrCarPlay()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        cancellables.removeAll()
    }

    private func buildCarPlayRootTemplate() -> CPTemplate {
        let manager = GeminiLiveSessionManager.shared
        let vault = ConversationVaultClient.shared

        var sections: [CPListSection] = []

        // 1. Top Continuous Hands-Free Status Row (1-Tap Re-Trigger or Mute Toggle)
        let statusTitle: String
        if manager.audioEngine.isPlayingOutput {
            statusTitle = "🔊 Speaking • Tap to Skip / Interrupt"
        } else if manager.isProcessingCommand {
            statusTitle = "⚡ Thinking..."
        } else if manager.audioEngine.isCapturing {
            statusTitle = "🎙️ Listening Continuously • Speak Anytime"
        } else {
            statusTitle = "▶️ Tap to Start Continuous Voice Loop"
        }

        let subtitleText = !manager.liveModelTranscript.isEmpty
            ? manager.liveModelTranscript
            : "MS Copilot Loop Active • Stays listening after every answer"

        let liveVoiceItem = CPListItem(
            text: statusTitle,
            detailText: subtitleText,
            image: UIImage(systemName: manager.audioEngine.isPlayingOutput ? "speaker.wave.3.fill" : "waveform.circle.fill")
        )
        liveVoiceItem.handler = { _, completion in
            if manager.audioEngine.isPlayingOutput {
                manager.audioEngine.interruptPlaybackImmediately()
            } else {
                manager.startOrResumeFromSiriOrCarPlay()
            }
            completion()
        }

        let micSourceItem = CPListItem(
            text: manager.audioEngine.useCarBluetoothMic ? "🎤 Mic Input: Car Bluetooth (Tap for iPhone Mic)" : "📱 Mic Input: iPhone High-Gain Mic (Recommended)",
            detailText: "iPhone mic keeps car music playing & never drops on CarPlay"
        )
        micSourceItem.handler = { _, completion in
            manager.audioEngine.toggleMicInputSource()
            completion()
        }

        sections.append(CPListSection(items: [liveVoiceItem, micSourceItem], header: "CarSpeak • Continuous Hands-Free AI", sectionIndexTitle: nil))

        // 2. Saved Conversations Section
        if !vault.conversations.isEmpty {
            let threadItems: [CPListItem] = vault.conversations.prefix(8).map { thread in
                let item = CPListItem(
                    text: thread.title,
                    detailText: "\(thread.projectName ?? "General") • \(thread.summary)"
                )
                item.handler = { _, completion in
                    Task { @MainActor in
                        _ = await vault.switchConversation(queryOrId: thread.id)
                        await manager.sendVoiceOrTextCommand("Switch to our conversation \(thread.title) and summarize where we left off in two short sentences.")
                        completion()
                    }
                }
                return item
            }
            sections.append(CPListSection(items: threadItems, header: "Saved Conversations", sectionIndexTitle: nil))
        }

        // 3. Antigravity Projects Section (56 Projects)
        let projectItems: [CPListItem] = vault.agProjects.prefix(15).map { proj in
            let item = CPListItem(
                text: proj.displayName,
                detailText: "\(proj.category) • \(proj.recentFocus)"
            )
            item.handler = { _, completion in
                Task { @MainActor in
                    await manager.sendVoiceOrTextCommand("Let's pick up where we left off on \(proj.displayName). Summarize its focus in two sentences.")
                    completion()
                }
            }
            return item
        }
        sections.append(CPListSection(items: projectItems, header: "Antigravity Projects (\(vault.agProjects.count))", sectionIndexTitle: nil))

        return CPListTemplate(title: "CarSpeak • Copilot Loop", sections: sections)
    }
}
