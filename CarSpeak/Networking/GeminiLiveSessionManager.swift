import Foundation
import Combine
import UIKit

/// Path A: Native Full-Duplex Gemini Live Conversational Engine for CarSpeak.
///
/// Architecture (Zero SFSpeechRecognizer):
/// 1. Direct 16kHz PCM Streaming (`realtimeInput.audio`):
///    Streams captured microphone audio directly over the Gemini Live WebSocket.
///    During brief 5G tower reconnects, chunks buffer in `OutboxRingBuffer` and flush on `setupComplete`.
/// 2. Native Server-Side VAD & Barge-In:
///    Gemini Live detects speech boundaries, transcribes via `inputTranscription`, and sends
///    `interrupted: true` if Dr. Mohit speaks over a response.
/// 3. Streaming 24kHz Neural Audio Output (`Puck`, `Fenrir`, `Charon`, `Aoede`).
/// 4. In-Car Black-Box Diagnostics:
///    Publishes `sentAudioFramesCount`, `receivedAudioBytesCount`, and `lastSocketError` live.
final class GeminiLiveSessionManager: NSObject, ObservableObject {
    static let shared = GeminiLiveSessionManager()

    @Published var isLiveSessionActive: Bool = false
    @Published var connectionStatusText: String = "Tap to Start CarSpeak"
    @Published var currentPersona: PersonaMode = .executive
    @Published var liveUserTranscript: String = ""
    @Published var liveModelTranscript: String = ""
    @Published var telemetry = HandoffTelemetry()
    @Published var isProcessingCommand: Bool = false

    // Black-Box Telemetry
    @Published var sentAudioFramesCount: Int = 0
    @Published var receivedAudioBytesCount: Int = 0
    @Published var lastSocketError: String = "None"

    let audioEngine = CabinAudioEngine()
    let handoffMonitor = CellularHandoffMonitor()
    let vault = ConversationVaultClient.shared
    private let outboxBuffer = OutboxRingBuffer(maxFrames: 50)

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var resumptionHandle: String?
    private var isReconnecting: Bool = false
    private(set) var isSetupComplete: Bool = false
    private var shouldSendGreetingOnSetup: Bool = false
    private var lastReconnectTimestamp: Date = .distantPast
    private var pendingUserTranscriptBuffer: String = ""
    private var pendingModelTranscriptBuffer: String = ""
    private var pingTimer: Timer?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 3600.0
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)

        setupAudioAndHandoffCallbacks()
    }

    private func setupAudioAndHandoffCallbacks() {
        // 1. Direct 16kHz PCM audio stream -> Gemini Live realtimeInput.audio
        audioEngine.onPCM16ChunkCaptured = { [weak self] pcmData in
            guard let self = self, self.isLiveSessionActive else { return }

            if self.isSetupComplete, let ws = self.webSocketTask {
                self.sendRealtimeAudioChunk(pcmData, over: ws)
            } else {
                _ = self.outboxBuffer.enqueue(pcmData: pcmData)
                DispatchQueue.main.async {
                    self.telemetry.bufferedFramesCount = self.outboxBuffer.pendingCount
                }
            }
        }

        // 2. Network interface observer: heals cleanly upon returning from an offline blackout
        handoffMonitor.onProactiveHandoffDetected = { [weak self] newInterface in
            guard let self = self else { return }
            self.telemetry.networkInterface = newInterface
            self.telemetry.towerHandoffCount += 1
            if self.isLiveSessionActive && (self.webSocketTask == nil || !self.isSetupComplete) {
                self.resumptionHandle = nil
                self.reconnectLiveSocket(isResuming: false)
            }
        }
    }

    // MARK: - 1. Session Lifecycle (Start / Stop)

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
        sentAudioFramesCount = 0
        receivedAudioBytesCount = 0
        lastSocketError = "None"
        connectionStatusText = "Connecting Gemini Live..."
        telemetry.connectionState = "Connecting"
        audioEngine.startCabinDuplexStream()
        SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)

        Task {
            await connectLiveWebSocket(isResuming: false)
        }
    }

    func stopHandsFreeSession() {
        isLiveSessionActive = false
        isReconnecting = false
        isSetupComplete = false
        shouldSendGreetingOnSetup = false
        stopPingTimer()
        outboxBuffer.clear()

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        audioEngine.stopCabinDuplexStream()
        connectionStatusText = "Session Standby"
        telemetry.connectionState = "Standby"
        SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)
    }

    func cyclePersonaMode() {
        let all = PersonaMode.allCases
        if let idx = all.firstIndex(of: currentPersona) {
            let nextIdx = (idx + 1) % all.count
            currentPersona = all[nextIdx]
        }
        let announcement = "Switched to \(currentPersona.displayName) mode."
        connectionStatusText = announcement
        SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)

        if isLiveSessionActive && isSetupComplete {
            injectContextMessageIntoLiveSession(
                role: "user",
                text: "[System Directive: Switch active persona mode immediately to \(currentPersona.displayName). Confirm briefly in one natural sentence.]",
                turnComplete: true
            )
        }
    }

    // MARK: - 2. Real-Time Audio Streaming (`realtimeInput.audio`)

    func sendRealtimeAudioChunk(_ pcmData: Data, over ws: URLSessionWebSocketTask) {
        let payload: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": pcmData.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let str = String(data: data, encoding: .utf8) else { return }

        ws.send(.string(str)) { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.lastSocketError = "Send: \(error.localizedDescription)"
                } else {
                    self.sentAudioFramesCount += 1
                }
            }
        }
    }

    private func drainOutboxBuffer(over ws: URLSessionWebSocketTask) {
        let frames = outboxBuffer.drainPendingFrames()
        for frame in frames {
            if let pcmData = Data(base64Encoded: frame.base64PCM16) {
                sendRealtimeAudioChunk(pcmData, over: ws)
                outboxBuffer.markSent(sequenceId: frame.sequenceId)
            }
        }
        DispatchQueue.main.async {
            self.telemetry.bufferedFramesCount = self.outboxBuffer.pendingCount
        }
    }

    // MARK: - 3. Explicit Text / Quick Prompt Dispatch

    @MainActor
    func handleCompletedUserTurn(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lower = trimmed.lowercased()
        if lower == "disconnect" || lower == "goodbye" || lower == "exit" || lower == "stop listening" {
            stopHandsFreeSession()
            connectionStatusText = "Session Ended • Drive Safely"
            return
        }

        self.liveUserTranscript = trimmed
        self.liveModelTranscript = ""
        self.pendingUserTranscriptBuffer = trimmed
        self.pendingModelTranscriptBuffer = ""
        self.connectionStatusText = "Thinking..."
        self.telemetry.connectionState = "5G Live Active"
        SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)

        if isSetupComplete, webSocketTask != nil {
            injectContextMessageIntoLiveSession(role: "user", text: trimmed, turnComplete: true)
        } else {
            await sendTurnViaRESTFallback(trimmed)
        }
    }

    private func sendTurnViaRESTFallback(_ text: String) async {
        guard let url = URL(string: "\(vault.baseURL)/api/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "message": text,
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
                await MainActor.run {
                    self.vault.activeConversation = updatedConv
                }
            }
            if let reply = decoded.reply, !reply.isEmpty {
                await MainActor.run {
                    self.liveModelTranscript = reply
                    self.pendingModelTranscriptBuffer = reply
                    self.connectionStatusText = "Speaking..."
                    self.audioEngine.speakUtteranceFallback(reply)
                    self.commitTurnToVault()
                }
            }
        } catch {
            await MainActor.run {
                self.lastSocketError = "REST: \(error.localizedDescription)"
                self.connectionStatusText = "Reconnecting 5G..."
            }
        }
    }

    // MARK: - 4. 5G Tower Handoff Resilience & Reconnect Engine

    private func reconnectLiveSocket(isResuming: Bool) {
        guard isLiveSessionActive, !isReconnecting else { return }
        guard Date().timeIntervalSince(lastReconnectTimestamp) > 1.5 else { return }
        lastReconnectTimestamp = Date()
        isReconnecting = true
        isSetupComplete = false
        stopPingTimer()

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        let startTime = Date()
        Task {
            await connectLiveWebSocket(isResuming: isResuming)
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            await MainActor.run {
                self.telemetry.lastHandoffLatencyMs = elapsedMs
                self.isReconnecting = false
                if self.isSetupComplete {
                    self.connectionStatusText = "Live • Speak Naturally"
                    self.telemetry.connectionState = "5G Live Active"
                }
            }
        }
    }

    // MARK: - 5. Gemini Live WebSocket Connection & Protocol Handshake

    func connectLiveWebSocket(isResuming: Bool) async {
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
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode >= 400 {
                if isResuming {
                    self.resumptionHandle = nil
                    await connectLiveWebSocket(isResuming: false)
                    return
                }
                await MainActor.run {
                    self.lastSocketError = "Gateway HTTP \(httpResp.statusCode)"
                }
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let wsUrlString = json["wsUrl"] as? String,
                  let wsURL = URL(string: wsUrlString),
                  let setupPayload = json["setupPayload"] as? [String: Any] else {
                if isResuming {
                    self.resumptionHandle = nil
                    await connectLiveWebSocket(isResuming: false)
                    return
                }
                await MainActor.run {
                    self.connectionStatusText = "Live Gateway Busy — Retrying..."
                    self.telemetry.connectionState = "Retrying"
                    self.lastSocketError = "Invalid /api/live-session JSON"
                }
                return
            }

            let setupData = try JSONSerialization.data(withJSONObject: setupPayload)
            guard let setupString = String(data: setupData, encoding: .utf8) else { return }

            let task = urlSession.webSocketTask(with: wsURL)
            self.webSocketTask = task
            task.resume()

            // 1. Mandatory Protocol Handshake: Send BidiGenerateContentSetup frame
            try await task.send(.string(setupString))

            await MainActor.run {
                self.telemetry.connectionState = "Handshake Sent"
                self.connectionStatusText = "Handshake Sent • Awaiting Gemini Live..."
                self.startPingTimer()
            }

            receiveNextWebSocketMessage()
        } catch {
            self.resumptionHandle = nil
            await MainActor.run {
                self.lastSocketError = "Connect: \(error.localizedDescription)"
                self.connectionStatusText = "Reconnecting 5G..."
                self.telemetry.connectionState = "Reconnecting"
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if self.isLiveSessionActive {
                self.reconnectLiveSocket(isResuming: false)
            }
        }
    }

    private func receiveNextWebSocketMessage() {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
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
            case .failure(let error):
                DispatchQueue.main.async {
                    self.lastSocketError = "Recv: \(error.localizedDescription)"
                }
                if self.isLiveSessionActive && !self.isReconnecting {
                    self.resumptionHandle = nil
                    self.reconnectLiveSocket(isResuming: false)
                }
            }
        }
    }

    private func handleServerJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // 0. Setup Complete: Gemini Live is ready to stream audio!
        if json["setupComplete"] != nil {
            self.isSetupComplete = true
            AcousticEarcons.shared.play(.sessionReady)

            if let ws = self.webSocketTask {
                self.drainOutboxBuffer(over: ws)
            }

            if self.shouldSendGreetingOnSetup {
                self.shouldSendGreetingOnSetup = false
                let activeTitle = self.vault.activeConversation?.projectName ?? "all 56 Antigravity projects"
                self.injectContextMessageIntoLiveSession(
                    role: "user",
                    text: "Greet Dr. Mohit warmly in one brief spoken sentence and confirm you are listening for \(activeTitle).",
                    turnComplete: true
                )
            }

            DispatchQueue.main.async {
                self.connectionStatusText = "Live • Speak Naturally"
                self.telemetry.connectionState = "5G Live Active"
            }
            return
        }

        // 1. Session Resumption Handle Update
        if let resumptionUpdate = json["sessionResumptionUpdate"] as? [String: Any],
           let newHandle = resumptionUpdate["newHandle"] as? String, !newHandle.isEmpty {
            self.resumptionHandle = newHandle
        }

        // 2. Proactive GoAway signal before periodic server-side connection rollover
        if json["goAway"] != nil {
            self.resumptionHandle = nil
            self.reconnectLiveSocket(isResuming: false)
            return
        }

        // 3. Non-Blocking Voice Tool Calls
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            Task {
                await self.handleLiveFunctionCalls(functionCalls)
            }
        }

        // 4. Server Content (Real-Time 24kHz Streaming Audio, Input/Output Transcripts, Barge-In)
        if let serverContent = json["serverContent"] as? [String: Any] {
            if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
                self.audioEngine.interruptPlaybackImmediately()
                DispatchQueue.main.async {
                    self.connectionStatusText = "Listening..."
                    SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)
                }
            }

            if let inputTrans = serverContent["inputTranscription"] as? [String: Any],
               let userText = inputTrans["text"] as? String, !userText.isEmpty {
                pendingUserTranscriptBuffer += userText
                let normalizedSpeech = pendingUserTranscriptBuffer.lowercased()
                let stopPhrases = ["end session", "stop session", "stop listening", "disconnect", "goodbye"]
                if stopPhrases.contains(where: { normalizedSpeech.contains($0) }) {
                    DispatchQueue.main.async {
                        AcousticEarcons.shared.play(.micMuted)
                        self.stopHandsFreeSession()
                        self.connectionStatusText = "Session Ended"
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.liveUserTranscript = self.pendingUserTranscriptBuffer
                }
            }

            if let outputTrans = serverContent["outputTranscription"] as? [String: Any],
               let modelText = outputTrans["text"] as? String, !modelText.isEmpty {
                pendingModelTranscriptBuffer += modelText
                DispatchQueue.main.async {
                    self.liveModelTranscript = self.pendingModelTranscriptBuffer
                    self.connectionStatusText = "Speaking..."
                    SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: true)
                }
            }

            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let inlineData = part["inlineData"] as? [String: Any],
                       let base64Audio = inlineData["data"] as? String,
                       let audioChunk = Data(base64Encoded: base64Audio) {
                        DispatchQueue.main.async {
                            self.receivedAudioBytesCount += audioChunk.count
                        }
                        self.audioEngine.enqueueLiveOutputPCM24k(audioChunk)
                    }
                }
            }

            if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
                self.audioEngine.flushPlaybackBuffer()
                self.commitTurnToVault()
                DispatchQueue.main.async {
                    self.connectionStatusText = "Live • Speak Naturally"
                    SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)
                }
            }
        }
    }

    private func injectContextMessageIntoLiveSession(role: String, text: String, turnComplete: Bool) {
        guard let ws = webSocketTask, isSetupComplete else { return }

        let payload: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": role,
                        "parts": [
                            ["text": text]
                        ]
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

    private func handleLiveFunctionCalls(_ functionCalls: [[String: Any]]) async {
        var functionResponses: [[String: Any]] = []

        for fc in functionCalls {
            let callId = fc["id"] as? String ?? ""
            let name = fc["name"] as? String ?? ""
            let args = fc["args"] as? [String: Any] ?? [:]

            if name == "end_carspeak_session" {
                await MainActor.run {
                    AcousticEarcons.shared.play(.micMuted)
                    self.stopHandsFreeSession()
                    self.connectionStatusText = "Session Ended"
                }
                return
            }

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
                            SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)
                        }
                    }

                    functionResponses.append([
                        "id": callId,
                        "name": name,
                        "response": [
                            "result": resultObj
                        ]
                    ])
                }
            } catch {
                await MainActor.run {
                    self.lastSocketError = "Tool: \(error.localizedDescription)"
                }
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

    private func commitTurnToVault() {
        let u = pendingUserTranscriptBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = pendingModelTranscriptBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingUserTranscriptBuffer = ""
        pendingModelTranscriptBuffer = ""

        if !u.isEmpty || !m.isEmpty {
            Task { @MainActor in
                await self.vault.appendTurn(
                    userText: u.isEmpty ? nil : u,
                    modelText: m.isEmpty ? nil : m,
                    persona: self.currentPersona
                )
            }
        }
    }

    // MARK: - 6. Heartbeat Ping / Pong

    private func startPingTimer() {
        stopPingTimer()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self, let ws = self.webSocketTask, self.isLiveSessionActive else { return }
            ws.sendPing { error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.lastSocketError = "Ping: \(error.localizedDescription)"
                        if self.isLiveSessionActive && !self.isReconnecting {
                            self.resumptionHandle = nil
                            self.reconnectLiveSocket(isResuming: false)
                        }
                    }
                }
            }
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    // MARK: - 7. Direct Text Composer Dispatch

    @MainActor
    func sendVoiceOrTextCommand(_ command: String) async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isProcessingCommand = true
        defer { isProcessingCommand = false }

        await handleCompletedUserTurn(trimmed)
    }
}
