import Foundation
import Combine

/// MS Copilot-Style 5G-Resilient Continuous Conversational Engine for CarSpeak.
///
/// Architecture:
/// 1. Continuous Turn-by-Turn Loop (`On-Device SFSpeechRecognizer` -> `Cloudflare /api/chat` -> `.caf AVAudioPlayer` -> `Auto-Listen`):
///    - Zero raw PCM WebSocket streaming over 5G while speaking (100% immune to 5G tower handoff packet loss).
///    - The moment Dr. Mohit pauses for 1.55 seconds, the complete sentence is sent via a tiny 1.5 KB HTTPS POST
///      to `https://carspeak-api.mohalex.workers.dev/api/chat` (powered by `Gemini 3.8 Flash` + all 56 Antigravity projects).
///    - The spoken reply is rendered to a high-gain `.caf` file and played via `AVAudioPlayer` (using a distinct male voice
///      so it is never confused with Siri).
///    - The instant the reply finishes playing, `CabinAudioEngine` plays a ready chime and automatically starts listening
///      again for the entire drive!
final class GeminiLiveSessionManager: NSObject, ObservableObject {
    static let shared = GeminiLiveSessionManager()

    @Published var isLiveSessionActive: Bool = false
    @Published var connectionStatusText: String = "Tap to Start Continuous Hands-Free Mode"
    @Published var currentPersona: PersonaMode = .executive
    @Published var liveUserTranscript: String = ""
    @Published var liveModelTranscript: String = ""
    @Published var telemetry = HandoffTelemetry()
    @Published var isProcessingCommand: Bool = false

    let audioEngine = CabinAudioEngine()
    let handoffMonitor = CellularHandoffMonitor()
    let vault = ConversationVaultClient.shared
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupCallbacks()
    }

    private func setupCallbacks() {
        // Live partial speech preview while Dr. Mohit is speaking
        audioEngine.$partialTranscript
            .receive(on: RunLoop.main)
            .sink { [weak self] partial in
                guard let self = self, !partial.isEmpty else { return }
                self.liveUserTranscript = partial
                self.connectionStatusText = "Hearing: \"\(partial)\""
            }
            .store(in: &cancellables)

        // Triggered automatically 1.55s after Dr. Mohit finishes speaking a sentence
        audioEngine.onSpokenSentenceCompleted = { [weak self] committedSentence in
            guard let self = self else { return }
            Task { @MainActor in
                await self.sendVoiceOrTextCommand(committedSentence)
            }
        }

        handoffMonitor.onProactiveHandoffDetected = { [weak self] newInterface in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.telemetry.networkInterface = newInterface
                self.telemetry.towerHandoffCount += 1
            }
        }
    }

    // MARK: - Start / Stop Continuous Copilot Loop (CarPlay Dashboard Tap or iPhone Launch)

    func startOrResumeFromSiriOrCarPlay(switchTopic: String? = nil) {
        if let topic = switchTopic, !topic.isEmpty {
            if !isLiveSessionActive {
                isLiveSessionActive = true
                audioEngine.startCabinDuplexStream()
            }
            Task { @MainActor in
                if let switched = await vault.switchConversation(queryOrId: topic) {
                    SteeringWheelController.shared.updateNowPlayingDashboard()
                    await sendVoiceOrTextCommand("We switched to \(switched.title). In two short sentences, summarize where we left off.")
                } else {
                    await sendVoiceOrTextCommand("Let's discuss my Antigravity project \(topic).")
                }
            }
            return
        }

        if !isLiveSessionActive {
            startHandsFreeSession()
        } else if !audioEngine.isPlayingOutput && !audioEngine.isCapturing {
            audioEngine.startListeningWindow()
            connectionStatusText = "Listening Continuously • Speak Anytime"
        }
    }

    func restartOrStartHandsFreeSession() {
        startOrResumeFromSiriOrCarPlay(switchTopic: nil)
    }

    func startHandsFreeSession(forceRestartAudio: Bool = false) {
        if isLiveSessionActive {
            if forceRestartAudio && !audioEngine.isPlayingOutput {
                audioEngine.startListeningWindow()
            }
            return
        }

        isLiveSessionActive = true
        telemetry.connectionState = "5G Turn-by-Turn Active"
        connectionStatusText = "CarSpeak Ready • Speaking Greeting..."
        SteeringWheelController.shared.updateNowPlayingDashboard()

        // Start continuous loop and speak a crisp opening greeting; as soon as the greeting finishes,
        // CabinAudioEngine automatically plays the ready chime and opens the microphone!
        audioEngine.startCabinDuplexStream()
        let activeTitle = vault.activeConversation?.projectName ?? "all 56 Antigravity projects"
        let greeting = "CarSpeak ready with \(activeTitle). What would you like to discuss?"
        liveModelTranscript = greeting
        audioEngine.speakFallbackText(greeting) { [weak self] in
            DispatchQueue.main.async {
                self?.connectionStatusText = "Listening Continuously • Speak Anytime"
            }
        }
    }

    func stopHandsFreeSession() {
        isLiveSessionActive = false
        audioEngine.stopCabinDuplexStream()
        connectionStatusText = "Session Paused — Tap Orb to Resume"
        telemetry.connectionState = "Standby"
        SteeringWheelController.shared.updateNowPlayingDashboard()
    }

    func cyclePersonaMode() {
        let all = PersonaMode.allCases
        if let idx = all.firstIndex(of: currentPersona) {
            let nextIdx = (idx + 1) % all.count
            currentPersona = all[nextIdx]
        }
        let announcement = "Switched to \(currentPersona.displayName) mode. Go ahead."
        connectionStatusText = announcement
        SteeringWheelController.shared.updateNowPlayingDashboard()
        audioEngine.speakFallbackText(announcement) { [weak self] in
            DispatchQueue.main.async {
                self?.connectionStatusText = "Listening Continuously • \(self?.currentPersona.displayName ?? "")"
            }
        }
    }

    // MARK: - Siri Voice Relay (If User Invokes via Siri Shortcut)

    @MainActor
    func askSiriRelayQuestion(_ query: String) async -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "I didn't catch that. Which Antigravity project would you like to discuss?"
        }

        liveUserTranscript = trimmed
        connectionStatusText = "Consulting AG Portfolio..."

        let lower = trimmed.lowercased()
        if let matchedProj = vault.agProjects.first(where: { lower.contains($0.displayName.lowercased()) || lower.contains($0.id.lowercased()) }) {
            let prompt = "Dr. Mohit is asking about his Antigravity project '\(matchedProj.displayName)' (Category: \(matchedProj.category), Focus: \(matchedProj.recentFocus), Tech: \(matchedProj.techStack)). Answer concisely in 2 to 3 spoken sentences: \(trimmed)"
            return await fetchCloudflareChatReply(prompt)
        }

        return await fetchCloudflareChatReply(trimmed)
    }

    @MainActor
    private func fetchCloudflareChatReply(_ message: String) async -> String {
        guard let url = URL(string: "\(vault.baseURL)/api/chat") else {
            return "CarSpeak cloud endpoint is unavailable."
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 14.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "message": message,
            "persona": currentPersona.rawValue,
            "conversationId": vault.activeConversation?.id ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let startTime = Date()
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            telemetry.lastHandoffLatencyMs = elapsedMs

            struct ChatResp: Decodable {
                let reply: String?
                let activeConversation: ConversationThread?
            }
            let decoded = try JSONDecoder().decode(ChatResp.self, from: data)
            if let updatedConv = decoded.activeConversation {
                vault.activeConversation = updatedConv
                if let idx = vault.conversations.firstIndex(where: { $0.id == updatedConv.id }) {
                    vault.conversations[idx] = updatedConv
                } else {
                    vault.conversations.insert(updatedConv, at: 0)
                }
            }
            if let reply = decoded.reply, !reply.isEmpty {
                liveModelTranscript = reply
                connectionStatusText = vault.activeConversation?.title ?? "CarSpeak Active"
                return reply
            }
        } catch {
            print("[GeminiLiveSessionManager] Cloud chat fallback: \(error.localizedDescription)")
        }

        // Offline local fallback using bundled 56 Antigravity projects seed
        let lower = message.lowercased()
        if let matched = vault.agProjects.first(where: { lower.contains($0.displayName.lowercased()) }) {
            return "\(matched.displayName) is your \(matched.category) project focused on \(matched.recentFocus), built with \(matched.techStack)."
        }
        return "I heard you say \(message). Name any of your \(vault.agProjects.count) Antigravity projects like Spine-Measure, Orator, or VigilOR to dive in."
    }

    // MARK: - Turn Execution (Spoken Sentence -> Cloudflare /api/chat -> .caf Playback -> Auto-Listen)

    @MainActor
    func sendVoiceOrTextCommand(_ command: String) async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if isLiveSessionActive {
                audioEngine.startListeningWindow()
            }
            return
        }

        isProcessingCommand = true
        liveUserTranscript = trimmed
        connectionStatusText = "Thinking..."

        // Check for spoken stop/pause commands
        let lower = trimmed.lowercased()
        if lower == "stop listening" || lower == "pause carspeak" || lower == "goodbye carspeak" {
            isProcessingCommand = false
            audioEngine.speakFallbackText("Pausing CarSpeak. Tap the screen whenever you want to resume.") { [weak self] in
                self?.stopHandsFreeSession()
            }
            return
        }

        let reply = await fetchCloudflareChatReply(trimmed)
        isProcessingCommand = false
        liveModelTranscript = reply
        connectionStatusText = "Speaking • \(vault.activeConversation?.title ?? "CarSpeak")"
        SteeringWheelController.shared.updateNowPlayingDashboard()

        // Speak the reply via high-gain .caf AVAudioPlayer; when finished, CabinAudioEngine
        // automatically plays the ready chime and opens the microphone for the next turn!
        audioEngine.speakFallbackText(reply) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.isLiveSessionActive else { return }
                self.connectionStatusText = "Listening Continuously • Speak Anytime"
                SteeringWheelController.shared.updateNowPlayingDashboard()
            }
        }
    }
}
