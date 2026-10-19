import Foundation
import CarPlay
import UIKit
import Combine

/// Native CarPlay Scene Delegate supporting Apple's CarPlay Voice Based Conversation capability
/// (`CPVoiceControlTemplate`) alongside `CPListTemplate` for 1-tap switching across archived
/// conversations and Dr. Mohit's 56 Antigravity projects.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        SteeringWheelController.shared.configureRemoteCommands()
        GeminiLiveSessionManager.shared.startHandsFreeSession()

        let rootTemplate = buildCarPlayRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)

        // Automatically refresh CarPlay list when projects or conversations update
        ConversationVaultClient.shared.$conversations
            .combineLatest(ConversationVaultClient.shared.$agProjects)
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                guard let self = self, let ic = self.interfaceController else { return }
                let updatedRoot = self.buildCarPlayRootTemplate()
                ic.setRootTemplate(updatedRoot, animated: false, completion: nil)
            }
            .store(in: &cancellables)
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

        // 1. Live Voice Co-Pilot Control Section (Always Available at Top)
        let liveVoiceItem = CPListItem(
            text: manager.isLiveSessionActive ? "🎙️ Active Live Voice Session (Tap for Voice HUD)" : "🎙️ Start Hands-Free Voice Conversation",
            detailText: "5G Multipath • Speak anytime or say 'Switch to project...'",
            image: UIImage(systemName: "waveform.circle.fill")
        )
        liveVoiceItem.handler = { [weak self] _, completion in
            manager.startHandsFreeSession(forceRestartAudio: true)
            self?.presentVoiceControlOverlay(
                title: vault.activeConversation?.title ?? "CarSpeak Hands-Free AI",
                subtitle: "Listening • 5G Live Stream"
            )
            completion()
        }
        sections.append(CPListSection(items: [liveVoiceItem], header: "Hands-Free Voice Control", sectionIndexTitle: nil))

        // 2. Saved Conversations Section (Only shown when non-empty)
        if !vault.conversations.isEmpty {
            let threadItems: [CPListItem] = vault.conversations.prefix(8).map { thread in
                let item = CPListItem(
                    text: thread.title,
                    detailText: "\(thread.projectName ?? "General") • \(thread.summary)"
                )
                item.handler = { [weak self] _, completion in
                    Task {
                        _ = await vault.switchConversation(queryOrId: thread.id)
                        await manager.sendVoiceOrTextCommand("Switch to our conversation \(thread.title) and summarize where we left off.")
                        self?.presentVoiceControlOverlay(title: thread.title, subtitle: thread.projectName ?? "Active Thread")
                        completion()
                    }
                }
                return item
            }
            sections.append(CPListSection(items: threadItems, header: "Saved Conversations", sectionIndexTitle: nil))
        }

        // 3. Previous Antigravity Projects Section
        let projectItems: [CPListItem] = vault.agProjects.prefix(12).map { proj in
            let item = CPListItem(
                text: proj.displayName,
                detailText: "\(proj.category) • \(proj.recentFocus)"
            )
            item.handler = { [weak self] _, completion in
                Task {
                    if !manager.isLiveSessionActive {
                        manager.startHandsFreeSession()
                    }
                    await manager.sendVoiceOrTextCommand("Let's pick up where we left off on \(proj.displayName).")
                    self?.presentVoiceControlOverlay(title: proj.displayName, subtitle: proj.category)
                    completion()
                }
            }
            return item
        }
        sections.append(CPListSection(items: projectItems, header: "Previous Antigravity Projects (\(vault.agProjects.count))", sectionIndexTitle: nil))

        let listTemplate = CPListTemplate(
            title: "CarSpeak • Hands-Free AI",
            sections: sections
        )
        return listTemplate
    }

    private func presentVoiceControlOverlay(title: String, subtitle: String) {
        guard let ic = interfaceController else { return }
        let state = CPVoiceControlState(
            identifier: "carspeak-active",
            titleVariants: [title, subtitle],
            image: UIImage(systemName: "waveform.circle.fill"),
            repeats: true
        )
        let voiceTemplate = CPVoiceControlTemplate(voiceControlStates: [state])
        ic.presentTemplate(voiceTemplate, animated: true, completion: nil)
    }
}
