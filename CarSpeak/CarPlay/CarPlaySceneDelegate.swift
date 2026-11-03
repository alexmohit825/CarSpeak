import Foundation
import CarPlay
import UIKit

/// CarPlay Dashboard Scene Delegate for CarSpeak.
/// Acts as a passive mirror display and hands-free control surface for Dr. Mohit's Antigravity portfolio,
/// completely isolated from audio engine routing to prevent CAN-bus race conditions.
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var copilotTabTemplate: CPListTemplate?
    private var projectsTabTemplate: CPListTemplate?
    private var threadsTabTemplate: CPListTemplate?
    private var lastSectionRefreshTime: Date = .distantPast
    private var pendingRefreshWorkItem: DispatchWorkItem?

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        SteeringWheelController.shared.configureRemoteCommands()

        let copilotTab = buildCopilotTabTemplate()
        let projectsTab = buildProjectsTabTemplate()
        let threadsTab = buildThreadsTabTemplate()

        self.copilotTabTemplate = copilotTab
        self.projectsTabTemplate = projectsTab
        self.threadsTabTemplate = threadsTab

        let tabBar = CPTabBarTemplate(templates: [copilotTab, projectsTab, threadsTab])
        interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)

        // Only start session if not already running on iPhone
        let manager = GeminiLiveSessionManager.shared
        if !manager.isLiveSessionActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !manager.isLiveSessionActive {
                    manager.startHandsFreeSession()
                }
            }
        }
    }

    public func sceneWillEnterForeground(_ scene: UIScene) {
        SteeringWheelController.shared.configureRemoteCommands()
        refreshCopilotSections()
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // MARK: - Tab 1: Live Copilot & Controls

    private func buildCopilotTabTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Copilot", sections: buildCopilotSections())
        template.tabTitle = "Copilot"
        template.tabImage = UIImage(systemName: "waveform.circle.fill")
        return template
    }

    func refreshCopilotSections() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSectionRefreshTime)
        if elapsed >= 1.0 {
            lastSectionRefreshTime = now
            copilotTabTemplate?.updateSections(buildCopilotSections())
        } else {
            pendingRefreshWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.lastSectionRefreshTime = Date()
                self.copilotTabTemplate?.updateSections(self.buildCopilotSections())
            }
            pendingRefreshWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (1.0 - elapsed), execute: work)
        }
    }

    private func buildCopilotSections() -> [CPListSection] {
        let manager = GeminiLiveSessionManager.shared

        // 1. Primary Full-Duplex Voice Row
        let statusTitle: String
        if manager.audioEngine.isPlayingOutput {
            statusTitle = "🔊 AI Speaking • Tap to Interrupt"
        } else if manager.isLiveSessionActive {
            statusTitle = "🎙️ Listening • Say 'Over' or Tap to Send"
        } else {
            statusTitle = "▶️ Tap to Start CarSpeak"
        }

        let subtitleText: String
        if !manager.liveModelTranscript.isEmpty {
            subtitleText = manager.liveModelTranscript
        } else {
            subtitleText = "Human neural voice • All 56 Antigravity projects active"
        }

        let liveVoiceItem = CPListItem(
            text: statusTitle,
            detailText: subtitleText,
            image: UIImage(systemName: manager.audioEngine.isPlayingOutput ? "speaker.wave.3.fill" : "waveform.circle.fill")
        )
        liveVoiceItem.handler = { _, completion in
            if manager.audioEngine.isPlayingOutput {
                manager.audioEngine.interruptPlaybackImmediately()
            } else if manager.isLiveSessionActive {
                manager.audioEngine.speechTranscriber.forceSubmitCurrentTranscript()
            } else {
                manager.startHandsFreeSession()
            }
            completion()
        }

        // 2. Open CarPlay Now Playing Transport Screen
        let nowPlayingItem = CPListItem(
            text: "🎛️ Open CarPlay Now Playing Controls",
            detailText: "Steering wheel Play/Pause, Skip & Persona mode controls",
            image: UIImage(systemName: "play.circle.fill")
        )
        nowPlayingItem.handler = { [weak self] _, completion in
            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            completion()
        }

        // 3. Persona Mode Cycle
        let personaItem = CPListItem(
            text: "🧠 Persona: \(manager.currentPersona.displayName)",
            detailText: "Tap to cycle Executive, Surgical, Architect, Roadmap",
            image: UIImage(systemName: "sparkles")
        )
        personaItem.handler = { _, completion in
            manager.cyclePersonaMode()
            completion()
        }

        let controlSection = CPListSection(
            items: [liveVoiceItem, nowPlayingItem, personaItem],
            header: "CarSpeak • Continuous In-Car Partner",
            sectionIndexTitle: nil
        )

        // 4. 1-Tap Spoken Briefings
        let quickPrompts: [(title: String, detail: String, query: String)] = [
            (
                "📊 Portfolio Executive Briefing",
                "Spoken summary of active Antigravity projects",
                "Give me a crisp two-sentence executive briefing on my active Antigravity projects and ask which one I want to dive into."
            ),
            (
                "🦴 Spine-Measure & PJKPredict",
                "Spoken update on spinal deformity & measurement tools",
                "Summarize the current architecture and next milestones for Spine-Measure and PJKPredict in two spoken sentences."
            ),
            (
                "🗣️ Orator & Hands-Free Lingo",
                "Spoken update on CarPlay voice & audio learning apps",
                "Summarize the status of Orator and Hands-Free Lingo in two spoken sentences."
            ),
            (
                "🏥 VigilOR & NeuroCall",
                "Spoken update on neurosurgical call & OR intelligence",
                "Summarize the status of VigilOR and NeuroCall in two spoken sentences."
            )
        ]

        let quickItems: [CPListItem] = quickPrompts.map { prompt in
            let item = CPListItem(
                text: prompt.title,
                detailText: prompt.detail,
                image: UIImage(systemName: "bolt.circle.fill")
            )
            item.handler = { _, completion in
                Task { @MainActor in
                    await manager.sendVoiceOrTextCommand(prompt.query)
                    completion()
                }
            }
            return item
        }

        let quickSection = CPListSection(
            items: quickItems,
            header: "Quick Consultations",
            sectionIndexTitle: nil
        )

        return [controlSection, quickSection]
    }

    // MARK: - Tab 2: 56 Antigravity Projects

    private func buildProjectsTabTemplate() -> CPListTemplate {
        let vault = ConversationVaultClient.shared
        let projects = vault.agProjects

        let items: [CPListItem] = projects.prefix(18).map { proj in
            let item = CPListItem(
                text: proj.displayName,
                detailText: "\(proj.category) • \(proj.recentFocus)",
                image: UIImage(systemName: "folder.fill")
            )
            item.handler = { _, completion in
                Task { @MainActor in
                    await GeminiLiveSessionManager.shared.sendVoiceOrTextCommand(
                        "Let's focus on \(proj.displayName). Summarize our current status and roadmap in two concise spoken sentences."
                    )
                    completion()
                }
            }
            return item
        }

        let section = CPListSection(items: items, header: "Antigravity Projects (\(projects.count))", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "Projects", sections: [section])
        template.tabTitle = "Projects"
        template.tabImage = UIImage(systemName: "folder.badge.gearshape")
        return template
    }

    // MARK: - Tab 3: Saved Conversations Vault

    private func buildThreadsTabTemplate() -> CPListTemplate {
        let vault = ConversationVaultClient.shared
        let convs = vault.conversations

        let items: [CPListItem] = convs.prefix(12).map { conv in
            let item = CPListItem(
                text: conv.title,
                detailText: "\(conv.projectName ?? "General") • \(conv.turns.count) turns",
                image: UIImage(systemName: "bubble.left.and.bubble.right.fill")
            )
            item.handler = { _, completion in
                Task { @MainActor in
                    _ = await vault.switchConversation(queryOrId: conv.id)
                    await GeminiLiveSessionManager.shared.sendVoiceOrTextCommand(
                        "We just switched to \(conv.title). Summarize where we left off in two sentences."
                    )
                    completion()
                }
            }
            return item
        }

        let section = CPListSection(items: items, header: "Saved Threads (\(convs.count))", sectionIndexTitle: nil)
        let template = CPListTemplate(title: "History", sections: [section])
        template.tabTitle = "History"
        template.tabImage = UIImage(systemName: "clock.arrow.circlepath")
        return template
    }
}
