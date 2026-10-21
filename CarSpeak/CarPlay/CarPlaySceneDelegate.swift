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
        GeminiLiveSessionManager.shared.startOrResumeFromSiriOrCarPlay()

        let rootTemplate = buildCarPlayRootTemplate()
        interfaceController.setRootTemplate(rootTemplate, animated: true, completion: nil)

        // Present native CarPlay Voice Control screen immediately so the car screen matches a voice co-pilot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.presentVoiceControlOverlay(
                title: ConversationVaultClient.shared.activeConversation?.title ?? "CarSpeak • Listening Now",
                subtitle: "Speak Anytime • Tap Back for 56 Projects & Threads"
            )
        }

        // Automatically refresh CarPlay list when projects, conversations, or live transcript update
        ConversationVaultClient.shared.$conversations
            .combineLatest(ConversationVaultClient.shared.$agProjects, GeminiLiveSessionManager.shared.$liveModelTranscript)
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _ in
                guard let self = self, let ic = self.interfaceController else { return }
                let updatedRoot = self.buildCarPlayRootTemplate()
                ic.setRootTemplate(updatedRoot, animated: false, completion: nil)
            }
            .store(in: &cancellables)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Whenever Dr. Mohit opens CarSpeak on CarPlay (via Siri or dashboard tap), ensure the audio engine
        // and Gemini 3.8 Live session claim the cabin audio route and greet cleanly.
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

        // 1. Live Voice Co-Pilot Control Section (Always Available at Top)
        let activeSubtitle: String = {
            if !manager.liveModelTranscript.isEmpty {
                return manager.liveModelTranscript
            }
            return "Listening on CarPlay • Speak anytime or tap to greet"
        }()
        let liveVoiceItem = CPListItem(
            text: manager.isLiveSessionActive ? "🟢 CarSpeak Live • Listening Now" : "🎙️ Tap to Start CarSpeak Voice",
            detailText: activeSubtitle,
            image: UIImage(systemName: "waveform.circle.fill")
        )
        liveVoiceItem.handler = { [weak self] _, completion in
            manager.startOrResumeFromSiriOrCarPlay()
            self?.presentVoiceControlOverlay(
                title: vault.activeConversation?.title ?? "CarSpeak Hands-Free AI",
                subtitle: "Listening • Speak Anytime"
            )
            completion()
        }
        sections.append(CPListSection(items: [liveVoiceItem], header: "CarSpeak • \(manager.currentPersona.displayName)", sectionIndexTitle: nil))

        // 2. Saved Conversations Section (Only shown when non-empty)
        if !vault.conversations.isEmpty {
            let threadItems: [CPListItem] = vault.conversations.prefix(8).map { thread in
                let item = CPListItem(
                    text: thread.title,
                    detailText: "\(thread.projectName ?? "General") • \(thread.summary)"
                )
                item.handler = { [weak self] _, completion in
                    Task {
                        manager.audioEngine.ensureEngineRunning()
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
                    } else {
                        manager.audioEngine.ensureEngineRunning()
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
        // Avoid stacking duplicate CPVoiceControlTemplate instances if one is already presented
        if ic.presentedTemplate is CPVoiceControlTemplate {
            return
        }
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
