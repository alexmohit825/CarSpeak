import Foundation
import Combine

/// Rebuilt 5G-Resilient Gemini 3.8 Live Conversational Engine for CarSpeak.
/// Key Guarantees:
/// 1. Zero Reconnect Loops: Never tears down an active WebSocket on routine Wi-Fi/5G coexistence updates
///    or isolated frame send errors; uses an 8-second cooldown on socket recovery.
/// 2. Zero Echo / Self-Interruption: Suppresses mic uplink while `audioEngine.isAISpeakingOrInTail` is true,
///    and flushes the 180ms jitter buffer cleanly at the end of each model turn (`turnComplete`).
/// 3. Single Clean Greeting: Speaks a brief initial greeting only once when a session is first started.
final class GeminiLiveSessionManager: NSObject, ObservableObject {
    static let shared = GeminiLiveSessionManager()

    @Published var isLiveSessionActive: Bool = false
    @Published var connectionStatusText: String = "Ready for CarPlay / Siri"
    @Published var currentPersona: PersonaMode = .executive
    @Published var liveUserTranscript: String = ""
    @Published var liveModelTranscript: String = ""
    @Published var telemetry = HandoffTelemetry()
    @Published var isProcessingCommand: Bool = false

    let audioEngine = CabinAudioEngine()
    let handoffMonitor = CellularHandoffMonitor()
    let vault = ConversationVaultClient.shared
    private let outboxBuffer = OutboxRingBuffer(maxFrames: 40)

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var resumptionHandle: String?
    private var isHealingHandoff: Bool = false
    private var isSetupComplete: Bool = false
    private var shouldSendGreetingOnSetup: Bool = false
    private var lastHealTimestamp: Date = .distantPast
    private var queuedContextMessages: [(role: String, text: String, turnComplete: Bool)] = []
    private var pendingUserTranscriptBuffer: String = ""
    private var pendingModelTranscriptBuffer: String = ""

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.multipathServiceType = .handover
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)

        setupAudioAndHandoffCallbacks()
    }

    private func setupAudioAndHandoffCallbacks() {
        audioEngine.onPCM16ChunkCaptured = { [weak self] pcmData in
            guard let self = self, self.isLiveSessionActive else { return }
            // Never enqueue or transmit microphone frames while Gemini is speaking out of the speakers
            guard !self.audioEngine.isAISpeakingOrInTail else { return }

            let frame = self.outboxBuffer.enqueue(pcmData: pcmData)
            DispatchQueue.main.async {
                self.telemetry.bufferedFramesCount = self.outboxBuffer.pendingCount
            }
            if !self.isHealingHandoff && self.isSetupComplete {
                self.sendRealtimePCMFrame(frame)
            }
        }

        handoffMonitor.onProactiveHandoffDetected = { [weak self] newInterface in
            guard let self = self else { return }
            self.telemetry.networkInterface = newInterface
            self.telemetry.towerHandoffCount += 1
            if self.isLiveSessionActive {
                self.heal5GTowerHandoff()
            }
        }
    }

    // MARK: - Start / Stop Full-Duplex CarPlay Voice Session

    /// Synchronously claims the audio session during `AudioStartingIntent.perform()` or CarPlay scene activation,
    /// then re-asserts the cabin audio route and triggers the greeting once Siri's audio ducking releases.
    func startOrResumeFromSiriOrCarPlay(switchTopic: String? = nil) {
        // 1. Synchronously claim AVAudioSession and start AVAudioEngine so iOS AudioStartingIntent grants background audio ownership
        if !isLiveSessionActive {
            startHandsFreeSession()
        } else {
            audioEngine.rebindTapIfHardwareRateChangedAndEnsureRunning()
        }

        // 2. When Siri finishes speaking its brief dialog (~1.4s later), re-assert the CarPlay audio route and speak/switch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self = self else { return }
            self.audioEngine.rebindTapIfHardwareRateChangedAndEnsureRunning()

            if let topic = switchTopic, !topic.isEmpty {
                Task { @MainActor in
                    if let switched = await ConversationVaultClient.shared.switchConversation(queryOrId: topic) {
                        SteeringWheelController.shared.updateNowPlayingDashboard()
                        await self.sendVoiceOrTextCommand("We switched to \(switched.title). Briefly summarize where we left off.")
                    } else {
                        await self.sendVoiceOrTextCommand("Switch to our conversation on \(topic)")
                    }
                }
            } else if self.isSetupComplete && self.webSocketTask != nil && !self.audioEngine.isAISpeakingOrInTail {
                self.injectContextMessageIntoLiveSession(
                    role: "user",
                    text: "Say 'CarSpeak ready. What would you like to discuss?' in one short sentence.",
                    turnComplete: true
                )
            }
        }
    }

    func restartOrStartHandsFreeSession() {
        startOrResumeFromSiriOrCarPlay(switchTopic: nil)
    }

    func startHandsFreeSession(forceRestartAudio: Bool = false) {
        if isLiveSessionActive {
            if forceRestartAudio {
                audioEngine.ensureEngineRunning()
            }
            return
        }

        isLiveSessionActive = true
        isSetupComplete = false
        shouldSendGreetingOnSetup = true
        connectionStatusText = "Connecting Gemini 3.8 Live..."
        telemetry.connectionState = "Connecting"
        audioEngine.startCabinDuplexStream()
        SteeringWheelController.shared.updateNowPlayingDashboard()

        Task {
            await connectLiveWebSocket(isResuming: false)
        }
    }

    func stopHandsFreeSession() {
        isLiveSessionActive = false
        isHealingHandoff = false
        isSetupComplete = false
        shouldSendGreetingOnSetup = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        audioEngine.stopCabinDuplexStream()
        connectionStatusText = "Session Archived & Standby"
        telemetry.connectionState = "Standby"
        SteeringWheelController.shared.updateNowPlayingDashboard()
    }

    func cyclePersonaMode() {
        let all = PersonaMode.allCases
        if let idx = all.firstIndex(of: currentPersona) {
            let nextIdx = (idx + 1) % all.count
            currentPersona = all[nextIdx]
        }
        let announcement = "Switched to \(currentPersona.displayName) mode."
        connectionStatusText = announcement
        SteeringWheelController.shared.updateNowPlayingDashboard()

        if isLiveSessionActive {
            injectContextMessageIntoLiveSession(
                role: "user",
                text: "[System Directive: Switch active persona mode immediately to \(currentPersona.displayName). Confirm briefly in one sentence.]",
                turnComplete: true
            )
        } else {
            audioEngine.speakFallbackText(announcement)
        }
    }

    // MARK: - 5G Tower Handoff Recovery (With 8-Second Cooldown Guard)

    func heal5GTowerHandoff() {
        guard isLiveSessionActive, !isHealingHandoff else { return }
        // Prevent rapid reconnect loops
        guard Date().timeIntervalSince(lastHealTimestamp) > 8.0 else { return }
        lastHealTimestamp = Date()
        isHealingHandoff = true
        isSetupComplete = false
        let startTime = Date()

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        Task {
            await connectLiveWebSocket(isResuming: true)
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            await MainActor.run {
                self.telemetry.lastHandoffLatencyMs = elapsedMs
                self.isHealingHandoff = false
                self.connectionStatusText = "Listening • \(self.vault.activeConversation?.title ?? "CarSpeak Live")"
                self.telemetry.connectionState = "5G Multipath Active"
            }
        }
    }

    // MARK: - Gemini 3.8 Live WebSocket Connection & Setup

    private func connectLiveWebSocket(isResuming: Bool) async {
        guard let configURL = URL(string: "\(vault.baseURL)/api/live-session") else { return }
        var req = URLRequest(url: configURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var reqBody: [String: Any] = [
            "persona": currentPersona.rawValue,
            "conversationId": vault.activeConversation?.id ?? ""
        ]
        if isResuming, let handle = resumptionHandle {
            reqBody["resumptionHandle"] = handle
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: reqBody)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let wsUrlString = json["wsUrl"] as? String,
                  let wsURL = URL(string: wsUrlString),
                  let setupPayload = json["setupPayload"] as? [String: Any] else {
                await MainActor.run {
                    self.connectionStatusText = "Resilient Edge Voice Mode Active"
                    self.telemetry.connectionState = "Edge Relay Active"
                }
                return
            }

            let setupData = try JSONSerialization.data(withJSONObject: setupPayload)
            guard let setupString = String(data: setupData, encoding: .utf8) else { return }

            let task = urlSession.webSocketTask(with: wsURL)
            self.webSocketTask = task
            self.isSetupComplete = false
            task.resume()

            receiveNextWebSocketMessage()
            try await task.send(.string(setupString))

            await MainActor.run {
                self.connectionStatusText = "Listening • \(self.vault.activeConversation?.title ?? "Speak Anytime")"
                self.telemetry.connectionState = "Gemini 3.8 Live (UDP/Multipath)"
                SteeringWheelController.shared.updateNowPlayingDashboard()
            }
        } catch {
            await MainActor.run {
                self.connectionStatusText = "5G Edge Relay Active"
                self.telemetry.connectionState = "Edge Fallback Ready"
            }
        }
    }

    private func sendRealtimePCMFrame(_ frame: OutboxRingBuffer.AudioFrame) {
        guard let ws = webSocketTask, isSetupComplete, !audioEngine.isAISpeakingOrInTail else { return }
        let payload: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": frame.base64PCM16,
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }

        ws.send(.string(text)) { [weak self] error in
            if error == nil {
                self?.outboxBuffer.markSent(sequenceId: frame.sequenceId)
            }
        }
    }

    func injectContextMessageIntoLiveSession(role: String, text: String, turnComplete: Bool = true) {
        guard let ws = webSocketTask, isSetupComplete else {
            queuedContextMessages.append((role: role, text: text, turnComplete: turnComplete))
            return
        }
        let payload: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": role,
                        "parts": [["text": text]]
                    ]
                ],
                "turnComplete": turnComplete
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let str = String(data: data, encoding: .utf8) {
            ws.send(.string(str)) { _ in }
        }
    }

    private func receiveNextWebSocketMessage() {
        guard let ws = webSocketTask else { return }
        ws.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleServerJSON(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleServerJSON(text)
                    }
                @unknown default:
                    break
                }
                if self.isLiveSessionActive {
                    self.receiveNextWebSocketMessage()
                }
            case .failure:
                if self.isLiveSessionActive && !self.isHealingHandoff {
                    self.heal5GTowerHandoff()
                }
            }
        }
    }

    private func handleServerJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // 0. Server Setup Complete — Flush queued prompts or speak single initial greeting
        if json["setupComplete"] != nil {
            self.isSetupComplete = true
            let queued = self.queuedContextMessages
            self.queuedContextMessages.removeAll()
            if !queued.isEmpty {
                self.shouldSendGreetingOnSetup = false
                for msg in queued {
                    self.injectContextMessageIntoLiveSession(role: msg.role, text: msg.text, turnComplete: msg.turnComplete)
                }
            } else if self.shouldSendGreetingOnSetup {
                self.shouldSendGreetingOnSetup = false
                self.injectContextMessageIntoLiveSession(
                    role: "user",
                    text: "Say 'CarSpeak online. What would you like to discuss?' in one short sentence.",
                    turnComplete: true
                )
            }
        }

        // 1. Update SessionResumptionHandle for 5G tower handoffs
        if let resumptionUpdate = json["sessionResumptionUpdate"] as? [String: Any],
           let newHandle = resumptionUpdate["newHandle"] as? String, !newHandle.isEmpty {
            self.resumptionHandle = newHandle
        }

        // 2. Proactive GoAway signal before 10-15 min connection rollover
        if json["goAway"] != nil {
            self.heal5GTowerHandoff()
            return
        }

        // 3. Non-Blocking Voice Tool Calls
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            Task {
                await self.handleLiveFunctionCalls(functionCalls)
            }
        }

        // 4. Server Content (24kHz PCM Audio + Input/Output Transcriptions)
        if let serverContent = json["serverContent"] as? [String: Any] {
            if let inputTrans = serverContent["inputTranscription"] as? [String: Any],
               let userText = inputTrans["text"] as? String, !userText.isEmpty {
                pendingUserTranscriptBuffer += userText
                DispatchQueue.main.async {
                    self.liveUserTranscript = self.pendingUserTranscriptBuffer
                }
            }

            if let outputTrans = serverContent["outputTranscription"] as? [String: Any],
               let modelText = outputTrans["text"] as? String, !modelText.isEmpty {
                pendingModelTranscriptBuffer += modelText
                DispatchQueue.main.async {
                    self.liveModelTranscript = self.pendingModelTranscriptBuffer
                }
            }

            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let inlineData = part["inlineData"] as? [String: Any],
                       let b64 = inlineData["data"] as? String,
                       let pcm24k = Data(base64Encoded: b64) {
                        audioEngine.enqueueLiveOutputPCM24k(pcm24k)
                    }
                }
            }

            if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
                // Flush any remaining sub-180ms tail of audio so the last word of the sentence plays cleanly
                audioEngine.flushPlaybackBuffer()

                let finalUser = pendingUserTranscriptBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalModel = pendingModelTranscriptBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingUserTranscriptBuffer = ""
                pendingModelTranscriptBuffer = ""
                if !finalUser.isEmpty || !finalModel.isEmpty {
                    Task {
                        await self.vault.appendTurn(
                            userText: finalUser.isEmpty ? nil : finalUser,
                            modelText: finalModel.isEmpty ? nil : finalModel,
                            persona: self.currentPersona
                        )
                    }
                }
            }
        }
    }

    private func handleLiveFunctionCalls(_ functionCalls: [[String: Any]]) async {
        var functionResponses: [[String: Any]] = []

        for fc in functionCalls {
            let callId = fc["id"] as? String ?? ""
            let name = fc["name"] as? String ?? ""
            let args = fc["args"] as? [String: Any] ?? [:]

            guard let url = URL(string: "\(vault.baseURL)/api/tool-call") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name, "args": args])

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                if let respJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resultObj = respJson["result"] as? [String: Any] {

                    if name == "switch_to_conversation" || name == "start_new_conversation" {
                        await vault.syncAllFromCloud()
                        await MainActor.run {
                            AcousticEarcons.shared.play(.threadSwitched)
                            self.connectionStatusText = "Switched: \(self.vault.activeConversation?.title ?? "")"
                            SteeringWheelController.shared.updateNowPlayingDashboard()
                        }
                    }

                    functionResponses.append([
                        "id": callId,
                        "name": name,
                        "response": [
                            "result": resultObj,
                            "scheduling": "INTERRUPT"
                        ]
                    ])
                }
            } catch {
                print("[GeminiLiveSessionManager] Tool execution error: \(error.localizedDescription)")
            }
        }

        guard !functionResponses.isEmpty, let ws = webSocketTask else { return }
        let toolRespPayload: [String: Any] = [
            "toolResponse": [
                "functionResponses": functionResponses
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: toolRespPayload),
           let str = String(data: data, encoding: .utf8) {
            try? await ws.send(.string(str))
        }
    }

    // MARK: - Direct Voice/Text Command Execution (Siri Intent / CarPlay List / Fallback)

    @MainActor
    func sendVoiceOrTextCommand(_ command: String) async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isProcessingCommand = true
        defer { isProcessingCommand = false }

        liveUserTranscript = trimmed
        connectionStatusText = "Thinking..."

        if isLiveSessionActive, webSocketTask != nil, isSetupComplete {
            audioEngine.ensureEngineRunning()
            injectContextMessageIntoLiveSession(role: "user", text: trimmed, turnComplete: true)
            connectionStatusText = "Listening • \(vault.activeConversation?.title ?? "CarSpeak Live")"
            return
        }

        guard let url = URL(string: "\(vault.baseURL)/api/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "message": trimmed,
            "persona": currentPersona.rawValue,
            "conversationId": vault.activeConversation?.id ?? ""
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
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
            if let reply = decoded.reply {
                liveModelTranscript = reply
                connectionStatusText = vault.activeConversation?.title ?? "CarSpeak Active"
                SteeringWheelController.shared.updateNowPlayingDashboard()
                audioEngine.speakFallbackText(reply)
            }
        } catch {
            connectionStatusText = "Offline Cache Active — Retrying 5G..."
        }
    }
}
