import Foundation
import CarPlay
import UIKit

/// CarPlay Dashboard Scene Delegate for CarSpeak.
/// Acts as a clean, glanceable mirror display for Dr. Mohit's Antigravity portfolio,
/// completely stripped of clunky control menus and muting traps to prevent CAN-bus race conditions.
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

    // MARK: - Tab 1: Live Copilot & Glanceable Status

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
        let vault = ConversationVaultClient.shared

        // 1. Primary Status & Action Row (Zero Clutter)
        let statusTitle: String
        let subtitleText: String
        let statusImageName: String

        if manager.audioEngine.isPlayingOutput {
            statusTitle = "🔊 AI Speaking • Tap to Interrupt"
            subtitleText = !manager.liveModelTranscript.isEmpty
                ? String(manager.liveModelTranscript.prefix(90))
                : "Speaking through vehicle audio..."
            statusImageName = "speaker.wave.3.fill"
        } else if manager.isLiveSessionActive {
            statusTitle = "🎙️ Listening • Say 'Over' or Tap to Send"
            subtitleText = "Speak naturally. Say 'over' when you finish your thought."
            statusImageName = "waveform.circle.fill"
        } else {
            statusTitle = "▶️ Tap to Start CarSpeak Session"
            subtitleText = "Continuous hands-free neural partner for all 56 Antigravity projects"
            statusImageName = "play.circle.fill"
        }

        let liveVoiceItem = CPListItem(
            text: statusTitle,
            detailText: subtitleText,
            image: UIImage(systemName: statusImageName)
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

        // 2. Active Antigravity Project Glance
        let activeProjectTitle = vault.activeConversation?.projectName ?? "Antigravity Portfolio"
        let activeThreadSummary = vault.activeConversation?.summary.isEmpty == false
            ? String(vault.activeConversation!.summary.prefix(90))
            : "56 projects active • Neurosurgical, Medicolegal & Finance"

        let projectItem = CPListItem(
            text: "📁 Active Context: \(activeProjectTitle)",
            detailText: activeThreadSummary,
            image: UIImage(systemName: "folder.badge.gearshape.fill")
        )
        projectItem.handler = { _, completion in
            Task { @MainActor in
                await manager.sendVoiceOrTextCommand("Summarize our active Antigravity focus in two concise spoken sentences.")
                completion()
            }
        }

        // 3. Live Spoken Transcript Glance
        let transcriptDetail = !manager.liveModelTranscript.isEmpty
            ? manager.liveModelTranscript
            : (!manager.liveUserTranscript.isEmpty ? "Hearing: \"\(manager.liveUserTranscript)\"" : "Standing by for your first question.")

        let transcriptItem = CPListItem(
            text: "💬 Live Transcript",
            detailText: String(transcriptDetail.prefix(100)),
            image: UIImage(systemName: "bubble.left.and.bubble.right.fill")
        )
        transcriptItem.handler = { _, completion in
            completion()
        }

        let mainSection = CPListSection(
            items: [liveVoiceItem, projectItem, transcriptItem],
            header: "CarSpeak • Continuous In-Car Partner",
            sectionIndexTitle: nil
        )

        // 4. 1-Tap Quick Spoken Consultations
        let quickPrompts: [(title: String, detail: String, query: String)] = [
            (
                "📊 Portfolio Executive Briefing",
                "Spoken overview across active Antigravity projects",
                "Give me a crisp two-sentence executive briefing on my active Antigravity projects and ask which one I want to dive into."
            ),
            (
                "🦴 Spine-Measure & PJKPredict",
                "Status of spinal deformity & alignment tools",
                "Summarize the current architecture and next milestones for Spine-Measure and PJKPredict in two spoken sentences."
            ),
            (
                "🏥 VigilOR & NeuroCall",
                "Neurosurgical call & OR intelligence roadmap",
                "Summarize the status of VigilOR and NeuroCall in two spoken sentences."
            ),
            (
                "⚖️ MDEsq & CPTArmor",
                "Medicolegal & coding intelligence status",
                "Summarize the status of MDEsq and CPTArmor in two spoken sentences."
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
            header: "1-Tap Hands-Free Consultations",
            sectionIndexTitle: nil
        )

        return [mainSection, quickSection]
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
