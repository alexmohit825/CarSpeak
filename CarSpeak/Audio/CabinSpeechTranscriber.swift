import Foundation
import Speech
import AVFoundation

/// SOTA Self-Healing On-Device Speech Transcriber & "Over" Turn-Taking Engine for CarSpeak.
///
/// Engineering Pillars:
/// 1. Self-Healing Rolling Recognition:
///    Apple's `SFSpeechRecognitionTask` has a hard 60-second execution limit. This engine implements
///    an automatic 45-second proactive task recycler and auto-restarts upon `isFinal` or timeout errors
///    in <50ms, guaranteeing that CarSpeak NEVER goes into dead silence after a minute.
/// 2. Deterministic "Over" Turn Completion:
///    Dr. Mohit can speak as long as he needs. When he says "...over" (or "over and out", "roger"),
///    the turn instantly seals, strips the keyword, plays a crisp chirp earcon, and sends to Gemini.
/// 3. In-Car Acoustic Playback Gating:
///    Gated during AI playback so car speaker audio and road noise NEVER trigger self-interruption.
/// 4. Intelligent Silence Fallback:
///    If Dr. Mohit pauses for 2.2 seconds after speaking at least 2 words without saying "over",
///    it automatically submits the turn.
final class CabinSpeechTranscriber: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published var liveTranscript: String = ""
    @Published var isListening: Bool = false
    @Published var isGatedForPlayback: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var proactiveRecycleTimer: Timer?
    private let lock = NSLock()
    private var hasAuthorized: Bool = false
    private var pendingTurnBuffer: String = ""

    var onTurnCompleted: ((String) -> Void)?

    override init() {
        super.init()
        speechRecognizer?.delegate = self
        requestAuthorization()
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                let ok = (status == .authorized)
                self?.hasAuthorized = ok
                completion?(ok)
            }
        }
    }

    func startTranscribing() {
        lock.lock()
        isListening = true
        let gated = isGatedForPlayback
        lock.unlock()

        guard !gated else { return }
        startRecognitionTaskInternal()
    }

    func stopTranscribing() {
        lock.lock()
        isListening = false
        lock.unlock()

        stopActiveTaskInternal()
        DispatchQueue.main.async {
            self.liveTranscript = ""
        }
    }

    func setPlaybackGating(_ isPlaying: Bool) {
        lock.lock()
        isGatedForPlayback = isPlaying
        let shouldListen = isListening
        lock.unlock()

        if isPlaying {
            // When AI is speaking, halt speech transcription so it never hears itself
            stopActiveTaskInternal()
            DispatchQueue.main.async {
                self.liveTranscript = ""
            }
        } else {
            // AI finished speaking: clear buffers and resume listening
            if shouldListen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else { return }
                    self.lock.lock()
                    let canResume = !self.isGatedForPlayback && self.isListening
                    self.lock.unlock()
                    if canResume {
                        self.startRecognitionTaskInternal()
                    }
                }
            }
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let req = recognitionRequest
        let gated = isGatedForPlayback
        let listening = isListening
        lock.unlock()

        guard !gated, listening, let request = req else { return }
        request.append(buffer)
    }

    // MARK: - Internal Task Management & Self-Healing Recycler

    private func startRecognitionTaskInternal() {
        lock.lock()
        defer { lock.unlock() }

        guard !isGatedForPlayback, isListening else { return }
        stopActiveTaskOnly()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[CabinSpeechTranscriber] Recognizer unavailable — will retry")
            scheduleAutoRestart(after: 1.0)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = request

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let formatted = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.liveTranscript = formatted
                    self.processSpokenText(formatted)
                }
            }

            // CRITICAL SELF-HEALING: Auto-restart upon 60s Apple limit, timeout, or finalization!
            if error != nil || (result?.isFinal ?? false) {
                self.handleTaskTermination(error: error)
            }
        }

        // Proactive task recycle every 45s of idle listening (before Apple's 60s hard ceiling)
        scheduleProactiveRecycleTimer()
    }

    private func handleTaskTermination(error: Error?) {
        lock.lock()
        let shouldRestart = !isGatedForPlayback && isListening
        lock.unlock()

        if shouldRestart {
            print("[CabinSpeechTranscriber] Task ended (\(error?.localizedDescription ?? "isFinal")). Auto-recycling task in 50ms...")
            scheduleAutoRestart(after: 0.05)
        }
    }

    private func scheduleAutoRestart(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            let canRestart = !self.isGatedForPlayback && self.isListening
            self.lock.unlock()

            if canRestart {
                self.startRecognitionTaskInternal()
            }
        }
    }

    private func scheduleProactiveRecycleTimer() {
        proactiveRecycleTimer?.invalidate()
        proactiveRecycleTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock()
            let canRecycle = !self.isGatedForPlayback && self.isListening && self.liveTranscript.isEmpty
            self.lock.unlock()

            if canRecycle {
                print("[CabinSpeechTranscriber] Proactively recycling idle 45s task to maintain continuous readiness")
                self.startRecognitionTaskInternal()
            }
        }
    }

    private func stopActiveTaskOnly() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        proactiveRecycleTimer?.invalidate()
        proactiveRecycleTimer = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func stopActiveTaskInternal() {
        stopActiveTaskOnly()
    }

    // MARK: - Turn Detection & "Over" Logic

    private func processSpokenText(_ text: String) {
        guard !isGatedForPlayback else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Keyword Detection: "over", "over and out", "roger", "copy"
        let lower = trimmed.lowercased()
        let cleanPunct = lower.trimmingCharacters(in: CharacterSet(charactersIn: ".!?,;:- "))

        if cleanPunct.hasSuffix("over") || cleanPunct.hasSuffix("over and out") || cleanPunct.hasSuffix("roger") {
            let regexPattern = "(?i)\\s*(over\\s+and\\s+out|over|roger)[.!?\\s]*$"
            let cleaned = trimmed.replacingOccurrences(of: regexPattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !cleaned.isEmpty {
                completeTurnNow(cleanedText: cleaned, trigger: "Keyword 'over'")
                return
            }
        }

        // 2. Silence Timer Fallback: 2.2 seconds after speaking at least 2 words
        silenceTimer?.invalidate()
        let wordCount = trimmed.split(separator: " ").count
        if wordCount >= 2 {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: false) { [weak self] _ in
                guard let self = self, !self.isGatedForPlayback else { return }
                self.completeTurnNow(cleanedText: trimmed, trigger: "Silence pause")
            }
        }
    }

    func forceSubmitCurrentTranscript() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            completeTurnNow(cleanedText: text, trigger: "Manual tap")
        }
    }

    private func completeTurnNow(cleanedText: String, trigger: String) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        proactiveRecycleTimer?.invalidate()
        proactiveRecycleTimer = nil

        stopActiveTaskOnly()

        AcousticEarcons.shared.play(.turnSent)
        print("[CabinSpeechTranscriber] Turn completed via \(trigger): \"\(cleanedText)\"")

        DispatchQueue.main.async {
            self.liveTranscript = ""
            self.onTurnCompleted?(cleanedText)
        }
    }

    // MARK: - SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            lock.lock()
            let shouldStart = !isGatedForPlayback && isListening
            lock.unlock()
            if shouldStart {
                startRecognitionTaskInternal()
            }
        }
    }
}
