import Foundation
import CarPlay
import UIKit

/// Native CarPlay Scene Delegate supporting Apple's CarPlay Voice Based Conversation capability
/// (`CPVoiceControlTemplate`) alongside `CPListTemplate` for 1-tap switching across archived
/// conversations and Dr. Mohit's 56 Antigravity projects.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        SteeringWheelController.shared.configureRemoteCommands()
        GeminiLiveSessionManager.shared.startHandsFreeSession()

        let rootTemplate = buildCarPlayRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func buildCarPlayRootTemplate() -> CPTemplate {
        let manager = GeminiLiveSessionManager.shared
        let vault = ConversationVaultClient.shared

        // 1.Archived Conversations Section
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
        let archiveSection = CPListSection(items: threadItems, header: "Archived Conversations (Voice Switchable)", sectionIndexTitle: nil)

        // 2. Top Antigravity Projects Section
        let projectItems: [CPListItem] = vault.agProjects.prefix(12).map { proj in
            let item = CPListItem(
                text: proj.displayName,
                detailText: "\(proj.category) • \(proj.recentFocus)"
            )
            item.handler = { [weak self] _, completion in
                Task {
                    await manager.sendVoiceOrTextCommand("Pull up our Antigravity project \(proj.displayName) and tell me where we left off.")
                    self?.presentVoiceControlOverlay(title: proj.displayName, subtitle: proj.category)
                    completion()
                }
            }
            return item
        }
        let projectsSection = CPListSection(items: projectItems, header: "Antigravity Projects (56 Synced)", sectionIndexTitle: nil)

        let listTemplate = CPListTemplate(
            title: "CarSpeak • 5G Live",
            sections: [archiveSection, projectsSection]
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
