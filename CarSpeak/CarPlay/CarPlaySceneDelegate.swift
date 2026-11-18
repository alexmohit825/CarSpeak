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
        let projectCount = max(vault.agProjects.count, 69)

        // 1. Primary Voice Status Row (Clean, Minimalist, Zero Clutter)
        let statusTitle: String
        let subtitleText: String
        let statusImageName: String

        if manager.audioEngine.isPlayingOutput {
            statusTitle = "Speaking"
            subtitleText = "Tap to interrupt"
            statusImageName = "speaker.wave.3.fill"
        } else if manager.isLiveSessionActive {
            statusTitle = "Listening"
            subtitleText = "Speak naturally • Tap to pause"
            statusImageName = "waveform"
        } else {
            statusTitle = "Start CarSpeak"
            subtitleText = "All \(projectCount) Antigravity projects ready"
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
                manager.stopHandsFreeSession()
            } else {
                manager.startHandsFreeSession()
            }
            completion()
        }

        // 2. Active Project Context
        let activeProjectTitle = vault.activeConversation?.projectName ?? "All Antigravity Projects"
        let projectItem = CPListItem(
            text: activeProjectTitle,
            detailText: "Active project context",
            image: UIImage(systemName: "folder.fill")
        )
        projectItem.handler = { _, completion in
            Task { @MainActor in
                await manager.sendVoiceOrTextCommand("Summarize our active Antigravity focus in two concise spoken sentences.")
                completion()
            }
        }

        // 3. Latest Spoken Reply
        let transcriptDetail = !manager.liveModelTranscript.isEmpty
            ? manager.liveModelTranscript
            : (!manager.liveUserTranscript.isEmpty ? "Heard: \"\(manager.liveUserTranscript)\"" : "Ready when you are.")

        let transcriptItem = CPListItem(
            text: "Latest Response",
            detailText: String(transcriptDetail.prefix(90)),
            image: UIImage(systemName: "text.bubble.fill")
        )
        transcriptItem.handler = { _, completion in
            completion()
        }

        let mainSection = CPListSection(
            items: [liveVoiceItem, projectItem, transcriptItem],
            header: nil,
            sectionIndexTitle: nil
        )

        return [mainSection]
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
