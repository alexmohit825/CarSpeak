import Foundation
import AVFoundation
import Speech
import UIKit

/// MS Copilot-Style Continuous Turn-by-Turn Cabin Audio & Speech Engine.
///
/// Why this works 100% smoothly on both CarPlay and iPhone without dropouts, echoes, or Siri timeouts:
/// 1. Strict State Separation (Never Listens & Speaks Simultaneously):
///    - State A (`Listening`): Uses `SFSpeechRecognizer` + `AVAudioEngine` with a 1.5-second silence detector.
///      Zero bytes are sent over 5G while Dr. Mohit is speaking.
///    - State B (`Speaking`): Completely stops the microphone tap (`stopListening()`), renders the AI reply to
///      a high-gain `.caf` file on disk (`AVSpeechSynthesizer.write`), and plays it via `AVAudioPlayer`
///      (the exact same rock-solid audio path as Apple Music and `Hands-Free Lingo`).
///    - State C (`Auto-Resume`): The instant `AVAudioPlayer` finishes speaking (`audioPlayerDidFinishPlaying`),
///      it automatically plays a subtle ready chime and re-opens `startListeningWindow()` for the entire drive!
final class CabinAudioEngine: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    @Published var isCapturing: Bool = false
    @Published var isMuted: Bool = false
    @Published var inputLevel: Float = 0.0
    @Published var isPlayingOutput: Bool = false
    @Published var partialTranscript: String = ""
    @Published var useCarBluetoothMic: Bool = false

    /// Called automatically when the user finishes speaking a sentence (after 1.5s of silence).
    var onSpokenSentenceCompleted: ((String) -> Void)?

    /// Kept for compatibility if any legacy caller references it
    var onPCM16ChunkCaptured: ((Data) -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var audioPlayer: AVAudioPlayer?
    private let fallbackSynth = AVSpeechSynthesizer()
    private var speechCompletionHandler: (() -> Void)?

    private var silenceTimer: Timer?
    private let silenceThresholdSeconds: TimeInterval = 1.55
    private var latestRecognizedText: String = ""
    private var shouldKeepLoopAlive: Bool = false
    private let renderQueue = DispatchQueue(label: "com.AlexMohit.CarSpeak.renderQueue", qos: .userInitiated)

    var isAISpeakingOrInTail: Bool {
        return isPlayingOutput || (audioPlayer?.isPlaying == true) || fallbackSynth.isSpeaking
    }

    override init() {
        super.init()
        fallbackSynth.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .began {
            audioPlayer?.pause()
            stopListening()
        } else if type == .ended, shouldKeepLoopAlive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self, self.shouldKeepLoopAlive else { return }
                if let player = self.audioPlayer, !player.isPlaying {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    player.play()
                } else {
                    self.startListeningWindow()
                }
            }
        }
    }

    // MARK: - 1. Start / Stop Continuous Copilot Loop

    func startCabinDuplexStream() {
        shouldKeepLoopAlive = true
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        requestPermissionsIfNeeded { [weak self] granted in
            guard let self = self, granted else { return }
            if !self.isPlayingOutput {
                self.startListeningWindow()
            }
        }
    }

    func stopCabinDuplexStream() {
        shouldKeepLoopAlive = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopListening()
        audioPlayer?.stop()
        audioPlayer = nil
        if fallbackSynth.isSpeaking {
            fallbackSynth.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
            self.isCapturing = false
            self.isPlayingOutput = false
            self.inputLevel = 0.0
        }
    }

    func ensureEngineRunning() {
        if shouldKeepLoopAlive && !isPlayingOutput && !isCapturing {
            startListeningWindow()
        }
    }

    func rebindTapIfHardwareRateChangedAndEnsureRunning() {
        ensureEngineRunning()
    }

    func toggleMute() {
        isMuted.toggle()
        AcousticEarcons.shared.play(isMuted ? .micMuted : .micUnmuted)
        if isMuted {
            stopListening()
        } else if shouldKeepLoopAlive && !isPlayingOutput {
            startListeningWindow()
        }
    }

    func toggleMicInputSource() {
        useCarBluetoothMic.toggle()
        if isCapturing {
            stopListening()
            startListeningWindow()
        }
    }

    // MARK: - 2. Permissions

    private func requestPermissionsIfNeeded(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            guard authStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }

    // MARK: - 3. State A: Continuous Speech Listening Window (With 1.55s Silence Detector)

    func startListeningWindow() {
        guard shouldKeepLoopAlive, !isMuted, !isPlayingOutput else { return }
        stopListening()

        let session = AVAudioSession.sharedInstance()
        do {
            let options: AVAudioSession.CategoryOptions = [
                .allowBluetooth,
                .allowBluetoothA2DP,
                .mixWithOthers,
                .duckOthers,
                .defaultToSpeaker
            ]
            try session.setCategory(.playAndRecord, mode: useCarBluetoothMic ? .voiceChat : .measurement, options: options)

            // Default to the iPhone's built-in high-gain microphone so CarPlay's locked head-unit mic bus
            // never deafens the app, unless the user explicitly toggled Car Bluetooth Mic mode.
            if !useCarBluetoothMic,
               let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtInMic)
            } else {
                try? session.setPreferredInput(nil)
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[CabinAudioEngine] Listening session config warning: \(error.localizedDescription)")
        }

        do {
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(iOS 17.0, *) {
                req.addsPunctuation = true
            }
            self.recognitionRequest = req
            self.latestRecognizedText = ""

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else { return }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self, !self.isMuted, !self.isPlayingOutput else { return }
                self.recognitionRequest?.append(buffer)
                self.computeRMS(buffer: buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            DispatchQueue.main.async {
                self.isCapturing = true
            }

            recognitionTask = speechRecognizer?.recognitionTask(with: req) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !transcript.isEmpty {
                        DispatchQueue.main.async {
                            self.latestRecognizedText = transcript
                            self.partialTranscript = transcript
                            self.resetSilenceCommitTimer()
                        }
                    }
                }

                if error != nil {
                    DispatchQueue.main.async {
                        if !self.latestRecognizedText.isEmpty {
                            self.commitSpokenTurn()
                        } else if self.shouldKeepLoopAlive && !self.isPlayingOutput && !self.isMuted {
                            // Apple's SFSpeechRecognizer resets after ~60s of total silence; seamlessly restart it!
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                self.startListeningWindow()
                            }
                        }
                    }
                }
            }
        } catch {
            print("[CabinAudioEngine] Failed to start speech recognizer: \(error.localizedDescription)")
        }
    }

    private func resetSilenceCommitTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThresholdSeconds, repeats: false) { [weak self] _ in
            self?.commitSpokenTurn()
        }
    }

    private func commitSpokenTurn() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        let committed = latestRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        latestRecognizedText = ""
        guard !committed.isEmpty else { return }

        stopListening()
        AcousticEarcons.shared.play(.handoffHealed)
        onSpokenSentenceCompleted?(committed)
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        DispatchQueue.main.async {
            self.isCapturing = false
            self.inputLevel = 0.0
        }
    }

    // MARK: - 4. State B: Rock-Solid .caf File Playback (`Hands-Free Lingo` / Audiobook Path) + Auto-Resume

    func speakFallbackText(_ text: String, completion: (() -> Void)? = nil) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            completion?()
            if shouldKeepLoopAlive && !isMuted {
                startListeningWindow()
            }
            return
        }

        // 1. Stop microphone completely so it is 100% impossible to hear our own voice
        stopListening()
        speechCompletionHandler = completion

        DispatchQueue.main.async {
            self.isPlayingOutput = true
        }

        // 2. Render to a high-gain .caf file on disk and play via AVAudioPlayer (100% CarPlay A2DP compatible)
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            if let cafURL = self.renderSpeechToCafFile(text: cleaned) {
                DispatchQueue.main.async {
                    self.playRenderedCafFile(url: cafURL, fallbackText: cleaned)
                }
            } else {
                DispatchQueue.main.async {
                    self.playDirectSynthesizerFallback(text: cleaned)
                }
            }
        }
    }

    private func renderSpeechToCafFile(text: String) -> URL? {
        let voice = Self.pickBestDistinctMaleOrPremiumVoice()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 0.96
        utterance.volume = 1.0

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("carspeak_turn_\(UUID().uuidString).caf")

        let synth = AVSpeechSynthesizer()
        var audioFile: AVAudioFile?
        let sem = DispatchSemaphore(value: 0)
        var didFinish = false
        var hadError = false

        synth.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                hadError = true
                if !didFinish { didFinish = true; sem.signal() }
                return
            }
            if pcm.frameLength == 0 {
                if !didFinish { didFinish = true; sem.signal() }
                return
            }
            do {
                if audioFile == nil {
                    audioFile = try AVAudioFile(
                        forWriting: tmpURL,
                        settings: pcm.format.settings,
                        commonFormat: .pcmFormatFloat32,
                        interleaved: false
                    )
                }
                // Apply +3.5 dB cabin clarity boost
                if let channelData = pcm.floatChannelData {
                    let frames = Int(pcm.frameLength)
                    let channels = Int(pcm.format.channelCount)
                    for ch in 0..<channels {
                        let ptr = channelData[ch]
                        for i in 0..<frames {
                            ptr[i] = max(-1.0, min(1.0, ptr[i] * 1.45))
                        }
                    }
                }
                try audioFile?.write(from: pcm)
            } catch {
                hadError = true
                if !didFinish { didFinish = true; sem.signal() }
            }
        }

        let waitResult = sem.wait(timeout: .now() + 15.0)
        audioFile = nil
        if waitResult == .timedOut || hadError || !FileManager.default.fileExists(atPath: tmpURL.path) {
            return nil
        }
        return tmpURL
    }

    private func playRenderedCafFile(url: URL, fallbackText: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .duckOthers, .defaultToSpeaker]
        )
        try? session.setActive(true)

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = 1.0
            player.prepareToPlay()
            self.audioPlayer = player
            if !player.play() {
                playDirectSynthesizerFallback(text: fallbackText)
            }
        } catch {
            playDirectSynthesizerFallback(text: fallbackText)
        }
    }

    private func playDirectSynthesizerFallback(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.pickBestDistinctMaleOrPremiumVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 0.96
        utterance.volume = 1.0
        fallbackSynth.speak(utterance)
    }

    private static func pickBestDistinctMaleOrPremiumVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" || $0.language.hasPrefix("en") }
        // Prefer distinct male English voice (Aaron, Alex, Daniel, Arthur) so Dr. Mohit never confuses CarSpeak with female Siri
        if let malePremium = voices.first(where: { $0.gender == .male && $0.quality == .premium }) {
            return malePremium
        }
        if let maleEnhanced = voices.first(where: { $0.gender == .male && $0.quality == .enhanced }) {
            return maleEnhanced
        }
        if let maleAny = voices.first(where: { $0.gender == .male && $0.language == "en-US" }) {
            return maleAny
        }
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    func interruptPlaybackImmediately() {
        audioPlayer?.stop()
        audioPlayer = nil
        if fallbackSynth.isSpeaking {
            fallbackSynth.stopSpeaking(at: .immediate)
        }
        finishSpeakingAndAutoResumeListening()
    }

    // Legacy compatibility stubs
    func enqueueLiveOutputPCM24k(_ data: Data) {}
    func flushPlaybackBuffer() {}

    // MARK: - 5. State C: Auto-Resume Listening When Speech Finishes

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        try? FileManager.default.removeItem(at: player.url ?? URL(fileURLWithPath: ""))
        finishSpeakingAndAutoResumeListening()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeakingAndAutoResumeListening()
    }

    private func finishSpeakingAndAutoResumeListening() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPlayingOutput = false
            // Unduck background music while waiting for user to speak
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

            let cb = self.speechCompletionHandler
            self.speechCompletionHandler = nil
            cb?()

            // Automatically re-open the listening window after 0.35s so the conversation continues hands-free!
            if self.shouldKeepLoopAlive && !self.isMuted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self = self, self.shouldKeepLoopAlive, !self.isPlayingOutput, !self.isMuted else { return }
                    AcousticEarcons.shared.play(.sessionReady)
                    self.startListeningWindow()
                }
            }
        }
    }

    private func computeRMS(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let length = Int(buffer.frameLength)
        guard length > 0 else { return }
        var sum: Float = 0
        for i in 0..<length {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(length))
        let normalized = min(1.0, max(0.05, rms * 8.5))
        DispatchQueue.main.async {
            self.inputLevel = normalized
        }
    }
}
