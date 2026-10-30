import Foundation
import CarPlay
import UIKit

/// CarPlay Dashboard Scene Delegate for CarSpeak.
/// Integrates with CarPlay media audio routing, physical steering wheel controls,
/// and live voice session triggers for Dr. Mohit's Antigravity portfolio.
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

        // Automatically start the Gemini Live conversational session over CarPlay audio
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            GeminiLiveSessionManager.shared.startHandsFreeSession(forceRestartAudio: true)
        }
    }

    public func sceneWillEnterForeground(_ scene: UIScene) {
        SteeringWheelController.shared.configureRemoteCommands()
        let manager = GeminiLiveSessionManager.shared
        if !manager.isLiveSessionActive {
            manager.startHandsFreeSession(forceRestartAudio: true)
        }
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
        if elapsed >= 1.2 {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + (1.2 - elapsed), execute: work)
        }
    }

    private func buildCopilotSections() -> [CPListSection] {
        let manager = GeminiLiveSessionManager.shared

        // 1. Primary Full-Duplex Voice Row
        let statusTitle: String
        if manager.audioEngine.isPlayingOutput {
            statusTitle = "🔊 AI Speaking • Tap to Interrupt"
        } else if manager.isLiveSessionActive {
            statusTitle = "🎙️ Live • Speak Anytime (Full Duplex)"
        } else {
            statusTitle = "▶️ Tap to Connect Gemini Live"
        }

        let subtitleText: String
        if !manager.liveModelTranscript.isEmpty {
            subtitleText = manager.liveModelTranscript
        } else {
            subtitleText = "Human neural voice • Hardware echo cancellation active"
        }

        let liveVoiceItem = CPListItem(
            text: statusTitle,
            detailText: subtitleText,
            image: UIImage(systemName: manager.audioEngine.isPlayingOutput ? "speaker.wave.3.fill" : "waveform.circle.fill")
        )
        liveVoiceItem.handler = { _, completion in
            if manager.audioEngine.isPlayingOutput {
                manager.audioEngine.interruptPlaybackImmediately()
            } else if !manager.isLiveSessionActive {
                manager.startHandsFreeSession(forceRestartAudio: true)
            } else {
                manager.stopHandsFreeSession()
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
            if !manager.isLiveSessionActive {
                manager.startHandsFreeSession(forceRestartAudio: true)
            }
            completion()
        }

        // 3. Mute / Unmute Toggle
        let muteItem = CPListItem(
            text: manager.audioEngine.isMuted ? "🔇 Mic Muted (Tap to Unmute)" : "🎤 Cabin Mic Live (Tap to Mute)",
            detailText: "Mute microphone while continuing to hear audio",
            image: UIImage(systemName: manager.audioEngine.isMuted ? "mic.slash.fill" : "mic.fill")
        )
        muteItem.handler = { [weak self] _, completion in
            manager.audioEngine.toggleMute()
            self?.refreshCopilotSections()
            completion()
        }

        // 4. Persona Mode Cycle
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
            items: [liveVoiceItem, nowPlayingItem, muteItem, personaItem],
            header: "CarSpeak • Gemini Live Audio",
            sectionIndexTitle: nil
        )

        // 5. 1-Tap Spoken Briefings
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
            header: "1-Tap Spoken Briefings",
            sectionIndexTitle: nil
        )

        return [controlSection, quickSection]
    }

    // MARK: - Tab 2: All 56 Antigravity Projects

    private func buildProjectsTabTemplate() -> CPListTemplate {
        let vault = ConversationVaultClient.shared
        let manager = GeminiLiveSessionManager.shared

        let grouped = Dictionary(grouping: vault.agProjects, by: { $0.category })
        let sortedCategories = grouped.keys.sorted()

        let sections: [CPListSection] = sortedCategories.compactMap { category in
            guard let projects = grouped[category], !projects.isEmpty else { return nil }
            let items: [CPListItem] = projects.prefix(12).map { proj in
                let item = CPListItem(
                    text: proj.displayName,
                    detailText: proj.recentFocus,
                    image: UIImage(systemName: "folder.circle.fill")
                )
                item.handler = { _, completion in
                    Task { @MainActor in
                        await manager.sendVoiceOrTextCommand(
                            "Let's discuss my Antigravity project \(proj.displayName). Summarize its focus in two short spoken sentences."
                        )
                        completion()
                    }
                }
                return item
            }
            return CPListSection(items: items, header: category.uppercased(), sectionIndexTitle: nil)
        }

        let template = CPListTemplate(title: "AG Projects", sections: sections)
        template.tabTitle = "AG Projects"
        template.tabImage = UIImage(systemName: "folder.fill")
        return template
    }

    // MARK: - Tab 3: Saved Conversation Threads

    private func buildThreadsTabTemplate() -> CPListTemplate {
        let vault = ConversationVaultClient.shared
        let manager = GeminiLiveSessionManager.shared

        let threadItems: [CPListItem] = vault.conversations.prefix(15).map { thread in
            let item = CPListItem(
                text: thread.title,
                detailText: "\(thread.projectName ?? "General") • \(thread.summary)",
                image: UIImage(systemName: "bubble.left.and.bubble.right.fill")
            )
            item.handler = { _, completion in
                Task { @MainActor in
                    _ = await vault.switchConversation(queryOrId: thread.id)
                    await manager.sendVoiceOrTextCommand(
                        "Switch to our conversation \(thread.title) and summarize where we left off."
                    )
                    completion()
                }
            }
            return item
        }

        let section = CPListSection(
            items: threadItems,
            header: "Saved Conversations",
            sectionIndexTitle: nil
        )
        let template = CPListTemplate(title: "Threads", sections: [section])
        template.tabTitle = "Threads"
        template.tabImage = UIImage(systemName: "clock.fill")
        return template
    }
}
