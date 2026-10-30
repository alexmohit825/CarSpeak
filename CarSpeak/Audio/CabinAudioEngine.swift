import Foundation
import AVFoundation
import Speech
import UIKit
import CryptoKit

/// MS Copilot-Style Continuous Turn-by-Turn Cabin Audio & Speech Engine (CarPlay + iPhone).
///
/// Engineered specifically to match the proven `Hands-Free Lingo` CarPlay audio pipeline:
/// 1. Speaking State (`State B`):
///    - Always stops the microphone tap FIRST, clears `setPreferredInput(nil)`, and sets
///      `AVAudioSession` to `.playback` (`mode: .spokenAudio`, `options: [.allowBluetoothA2DP, .allowAirPlay, .duckOthers]`)
///      BEFORE rendering and playing the `.caf` file via `AVAudioPlayer`.
///    - Never calls `setActive(false)` between turns, so CarPlay holds the `.carAudio` stereo route continuously.
/// 2. Listening State (`State A`):
///    - Triggered ONLY after `audioPlayerDidFinishPlaying` completes.
///    - Creates a fresh `AVAudioEngine` instance so CarPlay route transitions never leave a stale sample rate on `inputNode`.
///    - The moment the user pauses for 1.55s (`commitSpokenTurn`), immediately stops `AVAudioEngine` and switches
///      `AVAudioSession` back to `.playback` so the upcoming AI response plays through the CarPlay stereo speakers.
final class CabinAudioEngine: NSObject, ObservableObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    @Published var isCapturing: Bool = false
    @Published var isMuted: Bool = false
    @Published var inputLevel: Float = 0.0
    @Published var isPlayingOutput: Bool = false
    @Published var partialTranscript: String = ""
    @Published var useCarBluetoothMic: Bool = false

    /// Called automatically when the user finishes speaking a sentence (after 1.55s of silence).
    var onSpokenSentenceCompleted: ((String) -> Void)?

    /// Kept for compatibility if any caller references it
    var onPCM16ChunkCaptured: ((Data) -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    private var audioPlayer: AVAudioPlayer?
    private let fallbackSynth = AVSpeechSynthesizer()
    private var speechCompletionHandler: (() -> Void)?

    private var silenceTimer: Timer?
    private let silenceThresholdSeconds: TimeInterval = 1.55
    private var latestRecognizedText: String = ""
    private var shouldKeepLoopAlive: Bool = false
    private let renderQueue = DispatchQueue(label: "com.AlexMohit.CarSpeak.AudioCache.render", qos: .userInitiated)

    var isAISpeakingOrInTail: Bool {
        return isPlayingOutput || (audioPlayer?.isPlaying == true) || fallbackSynth.isSpeaking
    }

    override init() {
        super.init()
        fallbackSynth.delegate = self
        _ = try? Self.ensureCacheDirectory()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .began {
            audioPlayer?.pause()
            stopListening(switchToPlaybackSession: false)
        } else if type == .ended, shouldKeepLoopAlive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self = self, self.shouldKeepLoopAlive else { return }
                if let player = self.audioPlayer, !player.isPlaying, self.isPlayingOutput {
                    self.configureCarPlayPlaybackSession()
                    player.play()
                } else if !self.isPlayingOutput && !self.isMuted {
                    self.startListeningWindow()
                }
            }
        }
    }

    // MARK: - 1. CarPlay-Safe Audio Session Configuration (`Hands-Free Lingo` Proven Path)

    /// Configures `AVAudioSession` for pure CarPlay stereo `.caf` playback (`State B`).
    /// Matches `Hands-Free Lingo/VoiceManager.swift` so CarPlay routes 100% of speech to the vehicle speakers.
    func configureCarPlayPlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setPreferredInput(nil)
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothA2DP, .allowAirPlay, .duckOthers]
            )
            try session.setActive(true, options: [])
        } catch {
            // Exact Hands-Free Lingo fallback if .duckOthers is rejected on a specific route
            try? session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
            try? session.setActive(true, options: [])
        }
    }

    // MARK: - 2. Start / Stop Continuous Copilot Loop

    /// Arms the continuous turn-by-turn loop and requests permissions if needed.
    /// Does NOT open the microphone if `openMicImmediately` is false (e.g. when a greeting is about to be spoken first).
    func startCabinDuplexStream(openMicImmediately: Bool = false) {
        shouldKeepLoopAlive = true
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        requestPermissionsIfNeeded { [weak self] granted in
            guard let self = self else { return }
            if openMicImmediately && granted && !self.isPlayingOutput && !self.isMuted {
                self.startListeningWindow()
            }
        }
    }

    func stopCabinDuplexStream() {
        shouldKeepLoopAlive = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopListening(switchToPlaybackSession: false)
        audioPlayer?.stop()
        audioPlayer = nil
        if fallbackSynth.isSpeaking {
            fallbackSynth.stopSpeaking(at: .immediate)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
            self.isCapturing = false
            self.isPlayingOutput = false
            self.inputLevel = 0.0
            SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)
        }
    }

    func ensureEngineRunning() {
        if shouldKeepLoopAlive && !isPlayingOutput && !isCapturing && !isMuted {
            startListeningWindow()
        }
    }

    func rebindTapIfHardwareRateChangedAndEnsureRunning() {
        ensureEngineRunning()
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            stopListening(switchToPlaybackSession: true)
        } else if shouldKeepLoopAlive && !isPlayingOutput {
            startListeningWindow()
        }
    }

    func toggleMicInputSource() {
        useCarBluetoothMic.toggle()
        if isCapturing && !isPlayingOutput {
            stopListening(switchToPlaybackSession: false)
            startListeningWindow()
        }
    }

    // MARK: - 3. Permissions

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

    // MARK: - 4. State A: Continuous Speech Listening Window (With 1.55s Silence Detector)

    func startListeningWindow() {
        guard shouldKeepLoopAlive, !isMuted, !isPlayingOutput else { return }
        stopListening(switchToPlaybackSession: false)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .mixWithOthers]
            )
            if !useCarBluetoothMic,
               let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtInMic)
            } else {
                try? session.setPreferredInput(nil)
            }
            try session.setActive(true, options: [])
        } catch {
            try? session.setPreferredInput(nil)
            try? session.setCategory(.playAndRecord, options: [.allowBluetooth, .mixWithOthers])
            try? session.setActive(true, options: [])
        }

        if !attemptStartAudioEngineTap(session: session) {
            // Automatic fallback: if preferred input failed on CarPlay, clear preferredInput and retry with default route
            try? session.setPreferredInput(nil)
            _ = attemptStartAudioEngineTap(session: session)
        }
    }

    private func attemptStartAudioEngineTap(session: AVAudioSession) -> Bool {
        do {
            let engine = AVAudioEngine()
            self.audioEngine = engine

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if #available(iOS 17.0, *) {
                req.addsPunctuation = true
            }
            self.recognitionRequest = req
            self.latestRecognizedText = ""

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                return false
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self, !self.isMuted, !self.isPlayingOutput else { return }
                self.recognitionRequest?.append(buffer)
                self.computeRMS(buffer: buffer)
            }

            engine.prepare()
            try engine.start()

            DispatchQueue.main.async {
                self.isCapturing = true
            }

            recognitionTask = speechRecognizer?.recognitionTask(with: req) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !transcript.isEmpty {
                        DispatchQueue.main.async {
                            guard !self.isPlayingOutput else { return }
                            self.latestRecognizedText = transcript
                            self.partialTranscript = transcript
                            self.resetSilenceCommitTimer()
                        }
                    }
                }

                if error != nil {
                    DispatchQueue.main.async {
                        guard !self.isPlayingOutput else { return }
                        if !self.latestRecognizedText.isEmpty {
                            self.commitSpokenTurn()
                        } else if self.shouldKeepLoopAlive && !self.isPlayingOutput && !self.isMuted {
                            // Seamlessly refresh Apple's 60-second idle recognition window
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                                guard let self = self, self.shouldKeepLoopAlive, !self.isPlayingOutput, !self.isMuted else { return }
                                self.startListeningWindow()
                            }
                        }
                    }
                }
            }
            return true
        } catch {
            print("[CabinAudioEngine] AudioEngine start warning: \(error.localizedDescription)")
            return false
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

        // Immediately stop listening and switch AVAudioSession back to CarPlay .playback mode
        stopListening(switchToPlaybackSession: true)
        onSpokenSentenceCompleted?(committed)
    }

    func stopListening(switchToPlaybackSession: Bool = false) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if switchToPlaybackSession {
            configureCarPlayPlaybackSession()
        }

        if Thread.isMainThread {
            self.isCapturing = false
            self.inputLevel = 0.0
        } else {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.inputLevel = 0.0
            }
        }
    }

    // MARK: - 5. State B: Rock-Solid .caf File Playback (`Hands-Free Lingo` Proven Path) + Auto-Resume

    func speakFallbackText(_ text: String, completion: (() -> Void)? = nil) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            completion?()
            if shouldKeepLoopAlive && !isMuted {
                startListeningWindow()
            }
            return
        }

        // 1. Synchronously mark output active & stop microphone so there is ZERO race condition with startListeningWindow
        if Thread.isMainThread {
            self.isPlayingOutput = true
        } else {
            DispatchQueue.main.sync {
                self.isPlayingOutput = true
            }
        }

        stopListening(switchToPlaybackSession: true)
        audioPlayer?.stop()
        audioPlayer = nil
        if fallbackSynth.isSpeaking {
            fallbackSynth.stopSpeaking(at: .immediate)
        }
        speechCompletionHandler = completion

        // 2. Render to .caf in Documents/AudioCache on serial renderQueue and play via AVAudioPlayer
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            if let cafURL = self.renderOrFetchCachedCafFile(text: cleaned) {
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

    private func renderOrFetchCachedCafFile(text: String) -> URL? {
        guard let voice = Self.pickVerifiedHumanVoice() else { return nil }
        let rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        let pitch: Float = 0.98
        let volume: Float = 1.0
        let postGain: Float = 1.45

        guard let cacheDir = try? Self.ensureCacheDirectory() else { return nil }
        let fileKey = Self.cacheKey(text: text, voiceID: voice.identifier, rate: rate, pitch: pitch, postGain: postGain)
        let destURL = cacheDir.appendingPathComponent("\(fileKey).caf")

        if FileManager.default.fileExists(atPath: destURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
           let fileSize = attrs[.size] as? UInt64,
           fileSize > 512 {
            return destURL
        }

        let tmpURL = cacheDir.appendingPathComponent("\(UUID().uuidString).tmp.caf")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.volume = volume
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.0

        let synth = AVSpeechSynthesizer()
        var audioFile: AVAudioFile?
        let sem = DispatchSemaphore(value: 0)
        var didFinish = false
        var hadError = false

        synth.write(utterance) { (buffer: AVAudioBuffer) in
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
                if let channelData = pcm.floatChannelData {
                    let frames = Int(pcm.frameLength)
                    let channels = Int(pcm.format.channelCount)
                    for ch in 0..<channels {
                        let ptr = channelData[ch]
                        for i in 0..<frames {
                            var v = ptr[i] * postGain
                            if v > 1.0 { v = 1.0 } else if v < -1.0 { v = -1.0 }
                            ptr[i] = v
                        }
                    }
                }
                try audioFile?.write(from: pcm)
            } catch {
                hadError = true
                if !didFinish { didFinish = true; sem.signal() }
            }
        }

        let waited = sem.wait(timeout: .now() + 25.0)
        let wroteAudio = (audioFile != nil)
        audioFile = nil

        if waited == .timedOut || hadError || !wroteAudio || !FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
            return nil
        }

        if FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.removeItem(at: destURL)
        }
        do {
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
            return destURL
        } catch {
            return tmpURL
        }
    }

    private func playRenderedCafFile(url: URL, fallbackText: String) {
        // Ensure AVAudioSession is in pure .playback CarPlay mode right before starting AVAudioPlayer
        configureCarPlayPlaybackSession()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = 1.0
            player.prepareToPlay()
            self.audioPlayer = player
            self.isPlayingOutput = true
            SteeringWheelController.shared.updateNowPlayingDashboard(
                duration: player.duration,
                elapsed: 0.0,
                isSpeaking: true
            )
            if !player.play() {
                playDirectSynthesizerFallback(text: fallbackText)
            }
        } catch {
            playDirectSynthesizerFallback(text: fallbackText)
        }
    }

    private func playDirectSynthesizerFallback(text: String) {
        configureCarPlayPlaybackSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.pickVerifiedHumanVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 0.98
        utterance.volume = 1.0
        SteeringWheelController.shared.updateNowPlayingDashboard(duration: 15.0, elapsed: 0.0, isSpeaking: true)
        fallbackSynth.speak(utterance)
    }

    /// Selects a natural human voice (preferring distinct British/US male voices like Daniel, Arthur, Oliver, Aaron
    /// so it is never confused with female US Siri, while strictly filtering out Apple novelty voices).
    private static func pickVerifiedHumanVoice() -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let preferredNames = ["Daniel", "Arthur", "Oliver", "Aaron", "Rishi", "Alex", "Samantha", "Ava", "Allison", "Karen", "Moira"]

        // 1. Check for premium/enhanced version of preferred human voices first
        for name in preferredNames {
            if let v = allVoices.first(where: { $0.name.localizedCaseInsensitiveContains(name) && $0.quality == .premium }) {
                return v
            }
            if let v = allVoices.first(where: { $0.name.localizedCaseInsensitiveContains(name) && $0.quality == .enhanced }) {
                return v
            }
        }
        // 2. Check for standard version of Daniel (en-GB male) or Aaron (en-US male) or Samantha (en-US)
        for name in preferredNames {
            if let v = allVoices.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                return v
            }
        }
        // 3. Exact Hands-Free Lingo fallback
        let exact = allVoices.filter { $0.language == "en-US" }
        if let v = exact.first(where: { $0.quality == .premium })
            ?? exact.first(where: { $0.quality == .enhanced })
            ?? exact.first {
            return v
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func ensureCacheDirectory() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("AudioCache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheKey(text: String, voiceID: String, rate: Float, pitch: Float, postGain: Float) -> String {
        var hasher = Insecure.SHA1()
        let combined = "\(text)|\(voiceID)|\(String(format: "%.3f", rate))|\(String(format: "%.3f", pitch))|\(String(format: "%.3f", postGain))"
        hasher.update(data: Data(combined.utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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

    // MARK: - 6. State C: Auto-Resume Listening When Speech Finishes

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finishSpeakingAndAutoResumeListening()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finishSpeakingAndAutoResumeListening()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeakingAndAutoResumeListening()
    }

    private func finishSpeakingAndAutoResumeListening() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isPlayingOutput = false
            SteeringWheelController.shared.updateNowPlayingDashboard(isSpeaking: false)

            let cb = self.speechCompletionHandler
            self.speechCompletionHandler = nil
            cb?()

            // Automatically re-open the listening window after 0.30s so the conversation continues hands-free!
            if self.shouldKeepLoopAlive && !self.isMuted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                    guard let self = self, self.shouldKeepLoopAlive, !self.isPlayingOutput, !self.isMuted else { return }
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
