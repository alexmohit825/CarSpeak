import Foundation
import CarPlay
import UIKit

/// CarPlay Dashboard Scene Delegate — Built on the exact proven `Hands-Free Lingo` `CPTabBarTemplate`
/// + `CPNowPlayingTemplate` + `.playback` `.caf` `AVAudioPlayer` architecture.
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var copilotTabTemplate: CPListTemplate?
    private var projectsTabTemplate: CPListTemplate?
    private var threadsTabTemplate: CPListTemplate?

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] didConnect interfaceController")
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

        // Update only the Copilot tab rows on turn state transitions (never spam setRootTemplate!)
        GeminiLiveSessionManager.shared.onCarPlayStateChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshCopilotSections()
            }
        }

        // Automatically speak the opening greeting over CarPlay stereo and enter continuous listening
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            GeminiLiveSessionManager.shared.startHandsFreeSession(forceRestartAudio: true)
        }
    }

    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        print("[CarPlay] didDisconnect")
        self.interfaceController = nil
        GeminiLiveSessionManager.shared.onCarPlayStateChanged = nil
    }

    // MARK: - Tab 1: Live Copilot & Controls

    private func buildCopilotTabTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Copilot", sections: buildCopilotSections())
        template.tabTitle = "Copilot"
        template.tabImage = UIImage(systemName: "waveform.circle.fill")
        return template
    }

    private func refreshCopilotSections() {
        copilotTabTemplate?.updateSections(buildCopilotSections())
    }

    private func buildCopilotSections() -> [CPListSection] {
        let manager = GeminiLiveSessionManager.shared

        // 1. Primary Voice Loop Action Row
        let statusTitle: String
        if manager.audioEngine.isPlayingOutput {
            statusTitle = "🔊 Speaking • Tap to Skip & Listen Now"
        } else if manager.isProcessingCommand {
            statusTitle = "⚡ Thinking • Consulting AG Portfolio..."
        } else if manager.audioEngine.isCapturing {
            statusTitle = "🎙️ Listening Continuously • Speak Anytime"
        } else {
            statusTitle = "▶️ Tap to Start Voice Loop (Speaks Greeting)"
        }

        let subtitleText = !manager.liveModelTranscript.isEmpty
            ? manager.liveModelTranscript
            : "MS Copilot Loop • Speaks via CarPlay & auto-listens after every answer"

        let liveVoiceItem = CPListItem(
            text: statusTitle,
            detailText: subtitleText,
            image: UIImage(systemName: manager.audioEngine.isPlayingOutput ? "speaker.wave.3.fill" : "waveform.circle.fill")
        )
        liveVoiceItem.handler = { _, completion in
            if manager.audioEngine.isPlayingOutput {
                manager.audioEngine.interruptPlaybackImmediately()
            } else {
                manager.startHandsFreeSession(forceRestartAudio: true)
            }
            completion()
        }

        // 2. Open CarPlay Now Playing Transport Screen (Proven Hands-Free Lingo Pattern)
        let nowPlayingItem = CPListItem(
            text: "🎛️ Open CarPlay Now Playing Controls",
            detailText: "Full-screen Play/Pause, Skip & Persona buttons on CarPlay",
            image: UIImage(systemName: "play.circle.fill")
        )
        nowPlayingItem.handler = { [weak self] _, completion in
            self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            if !manager.isLiveSessionActive {
                manager.startHandsFreeSession(forceRestartAudio: true)
            }
            completion()
        }

        // 3. Microphone Input Source Toggle
        let micSourceItem = CPListItem(
            text: manager.audioEngine.useCarBluetoothMic
                ? "🎤 Mic: Car Cabin (Tap for iPhone Mic)"
                : "📱 Mic: iPhone High-Gain (Tap for Car Mic)",
            detailText: "Switch anytime if your iPhone is in your pocket vs mounted",
            image: UIImage(systemName: "mic.circle.fill")
        )
        micSourceItem.handler = { [weak self] _, completion in
            manager.audioEngine.toggleMicInputSource()
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
            items: [liveVoiceItem, nowPlayingItem, micSourceItem, personaItem],
            header: "CarSpeak • Continuous Hands-Free AI",
            sectionIndexTitle: nil
        )

        // 5. 1-Tap Instant Spoken Briefings
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
                "Summarize the status of Orator and Hands-Free Lingo in two spoken sentences and ask what feature we should tackle next."
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
                            "Let's discuss my Antigravity project \(proj.displayName). Summarize its focus (\(proj.recentFocus)) in two short spoken sentences and ask what I want to work on."
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
                        "Switch to our conversation \(thread.title) and summarize where we left off in two short spoken sentences."
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
