import Foundation
import AVFoundation
import UIKit

/// Path A: Native Full-Duplex Cabin Audio Engine for CarSpeak.
///
/// Engineering Architecture (Zero SFSpeechRecognizer):
/// 1. Native CarPlay & Phone Routing:
///    Uses `.playAndRecord` with `.voiceChat` and `[.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker]`
///    WITHOUT forcing `setPreferredInput(.builtInMic)` against CarPlay's `.carAudio` bus.
/// 2. Direct 16kHz PCM Streaming:
///    Converts hardware mic frames (`inputNode`) directly into 16kHz 16-bit little-endian PCM
///    and delivers coalesced ~100ms chunks to Gemini Live (`realtimeInput.audio`).
/// 3. Streaming 24kHz Neural Audio Output:
///    Plays 24kHz PCM from Gemini Live via `AVAudioPlayerNode` (`Float32` non-interleaved).
/// 4. In-Car Black-Box Diagnostics:
///    Publishes live `activeInputRoute`, `activeOutputRoute`, `capturedFramesCount`, and `lastAudioError`
///    directly to the UI so there is zero blind guessing in the car.
final class CabinAudioEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isCapturing: Bool = false
    @Published var isMuted: Bool = false
    @Published var inputLevel: Float = 0.0
    @Published var isPlayingOutput: Bool = false

    // Black-Box Telemetry
    @Published var activeInputRoute: String = "Unknown"
    @Published var activeOutputRoute: String = "Unknown"
    @Published var capturedFramesCount: Int = 0
    @Published var lastAudioError: String = "None"

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let fallbackSynthesizer = AVSpeechSynthesizer()

    /// Standard 32-bit Float non-interleaved 24kHz mono format required by iOS AVAudioPlayerNode & AVAudioMixerNode
    let playbackFormat = AVAudioFormat(
        standardFormatWithSampleRate: 24000,
        channels: 1
    )!

    /// Standard 32-bit Float non-interleaved 16kHz mono format for hardware resampler
    private let float16kFormat = AVAudioFormat(
        standardFormatWithSampleRate: 16000,
        channels: 1
    )!

    private var shouldBeCapturing: Bool = false
    private var hasInstalledTap: Bool = false

    private let bufferLock = NSLock()
    private var activeScheduledBuffers: Int = 0
    private var pendingPlaybackData = Data()
    /// 120ms of 24kHz 16-bit mono PCM = 5760 bytes
    private let minCoalesceBytes: Int = 5760

    /// Coalesce ~100ms of 16kHz 16-bit mono PCM (3200 bytes) before sending over WebSocket
    private let captureLock = NSLock()
    private var pendingCaptureData = Data()
    private let minCaptureChunkBytes: Int = 3200

    /// Callback delivering 16kHz 16-bit linear PCM audio chunks for streaming to Gemini Live
    var onPCM16ChunkCaptured: ((Data) -> Void)?

    override init() {
        super.init()
        fallbackSynthesizer.delegate = self
        ensurePlayerNodeConnected()
        setupAudioSessionObservers()
        refreshRouteDiagnostics()
    }

    private func ensurePlayerNodeConnected() {
        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        }
    }

    private func setupAudioSessionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .began {
            playerNode.pause()
            fallbackSynthesizer.pauseSpeaking(at: .immediate)
            if audioEngine.isRunning {
                audioEngine.pause()
            }
            DispatchQueue.main.async {
                self.lastAudioError = "Audio interrupted by iOS"
            }
        } else if type == .ended {
            if shouldBeCapturing {
                ensureEngineRunning()
                playerNode.play()
                fallbackSynthesizer.continueSpeaking()
            }
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        refreshRouteDiagnostics()
        guard shouldBeCapturing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, self.shouldBeCapturing else { return }
            self.rebindHardwareTapIfNeeded()
        }
    }

    func refreshRouteDiagnostics() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inDesc = route.inputs.map { $0.portType.rawValue }.joined(separator: ",")
        let outDesc = route.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        DispatchQueue.main.async {
            self.activeInputRoute = inDesc.isEmpty ? "None" : inDesc
            self.activeOutputRoute = outDesc.isEmpty ? "None" : outDesc
        }
    }

    // MARK: - 1. Engine & Audio Session Lifecycle

    func startCabinDuplexStream() {
        shouldBeCapturing = true
        DispatchQueue.main.async {
            self.capturedFramesCount = 0
            self.lastAudioError = "None"
            UIApplication.shared.isIdleTimerDisabled = true
        }

        requestRecordPermission { [weak self] granted in
            guard let self = self, self.shouldBeCapturing else { return }
            if !granted {
                DispatchQueue.main.async {
                    self.lastAudioError = "Mic permission denied"
                }
                return
            }
            self.configureAudioSessionAndStart()
        }
    }

    func stopCabinDuplexStream() {
        shouldBeCapturing = false
        interruptPlaybackImmediately()

        captureLock.lock()
        pendingCaptureData = Data()
        captureLock.unlock()

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        refreshRouteDiagnostics()
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
            self.isCapturing = false
            self.isPlayingOutput = false
            self.inputLevel = 0.0
        }
    }

    func ensureEngineRunning() {
        guard shouldBeCapturing else { return }
        if !audioEngine.isRunning {
            configureAudioSessionAndStart()
        }
    }

    private func requestRecordPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }

    private func configureAudioSessionAndStart() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Native duplex options: allowBluetoothHFP lets CarPlay (.carAudio) and HFP use their duplex mic
            // without forcing setPreferredInput(.builtInMic) into a route war.
            let options: AVAudioSession.CategoryOptions = [
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .allowAirPlay,
                .defaultToSpeaker
            ]
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try session.setPreferredSampleRate(24000)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true, options: [])
        } catch {
            DispatchQueue.main.async {
                self.lastAudioError = "Session: \(error.localizedDescription)"
            }
        }

        refreshRouteDiagnostics()
        attachAndStartNodes()
    }

    private func attachAndStartNodes() {
        ensurePlayerNodeConnected()

        let inputNode = audioEngine.inputNode
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            // VoiceProcessingIO can fail on some simulators or non-duplex routes; keep running without crashing
            DispatchQueue.main.async {
                self.lastAudioError = "AEC skipped: \(error.localizedDescription)"
            }
        }

        installInputTap(inputNode: inputNode)

        do {
            audioEngine.prepare()
            try audioEngine.start()
            playerNode.play()
            DispatchQueue.main.async {
                self.isCapturing = true
            }
        } catch {
            DispatchQueue.main.async {
                self.lastAudioError = "Engine: \(error.localizedDescription)"
            }
        }
        refreshRouteDiagnostics()
    }

    private func installInputTap(inputNode: AVAudioInputNode) {
        guard !hasInstalledTap else { return }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            DispatchQueue.main.async {
                self.lastAudioError = "Input format invalid (\(recordingFormat.sampleRate)Hz)"
            }
            return
        }

        let converter = AVAudioConverter(from: recordingFormat, to: float16kFormat)
        let targetFormat = float16kFormat

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, !self.isMuted else { return }

            self.computeRMS(buffer: buffer)

            guard let converter = converter else { return }
            let ratio = 16000.0 / recordingFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard let floatBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            var didProvideBuffer = false
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if didProvideBuffer {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didProvideBuffer = true
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: floatBuffer, error: &error, withInputFrom: inputBlock)

            guard error == nil, floatBuffer.frameLength > 0,
                  let floatData = floatBuffer.floatChannelData?[0] else { return }

            let frames = Int(floatBuffer.frameLength)
            var pcm16Data = Data(count: frames * MemoryLayout<Int16>.size)
            pcm16Data.withUnsafeMutableBytes { rawBytes in
                guard let pcmPtr = rawBytes.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0..<frames {
                    let sample = max(-1.0, min(1.0, floatData[i]))
                    pcmPtr[i] = Int16(sample * 32767.0)
                }
            }

            self.captureLock.lock()
            self.pendingCaptureData.append(pcm16Data)
            var chunkToSend: Data? = nil
            if self.pendingCaptureData.count >= self.minCaptureChunkBytes {
                chunkToSend = self.pendingCaptureData
                self.pendingCaptureData = Data()
            }
            self.captureLock.unlock()

            if let chunk = chunkToSend {
                DispatchQueue.main.async {
                    self.capturedFramesCount += 1
                }
                self.onPCM16ChunkCaptured?(chunk)
            }
        }

        hasInstalledTap = true
    }

    private func rebindHardwareTapIfNeeded() {
        guard shouldBeCapturing else { return }
        let inputNode = audioEngine.inputNode
        let currentFormat = inputNode.outputFormat(forBus: 0)
        if currentFormat.sampleRate > 0 {
            inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
            installInputTap(inputNode: inputNode)
        }
    }

    // MARK: - 2. Streaming 24kHz Neural Audio Playback & Jitter Coalescing

    func enqueueLiveOutputPCM24k(_ data: Data) {
        guard data.count >= 2 else { return }

        bufferLock.lock()
        pendingPlaybackData.append(data)
        let shouldFlushNow = pendingPlaybackData.count >= minCoalesceBytes
        var chunkToSchedule: Data? = nil
        if shouldFlushNow {
            chunkToSchedule = pendingPlaybackData
            pendingPlaybackData = Data()
        }
        bufferLock.unlock()

        if let chunk = chunkToSchedule {
            scheduleCoalescedPCM24k(chunk)
        }
    }

    func flushPlaybackBuffer() {
        bufferLock.lock()
        let remaining = pendingPlaybackData
        pendingPlaybackData = Data()
        bufferLock.unlock()

        if remaining.count >= 2 {
            scheduleCoalescedPCM24k(remaining)
        }
    }

    private func scheduleCoalescedPCM24k(_ data: Data) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.ensurePlayerNodeConnected()
            if !self.audioEngine.isRunning {
                if self.shouldBeCapturing {
                    self.ensureEngineRunning()
                } else {
                    self.audioEngine.prepare()
                    try? self.audioEngine.start()
                    self.playerNode.play()
                }
            }
            guard self.playerNode.outputFormat(forBus: 0).channelCount == self.playbackFormat.channelCount else {
                self.lastAudioError = "Playback channel mismatch"
                return
            }

            let sampleCount = data.count / MemoryLayout<Int16>.size
            let frameCount = AVAudioFrameCount(sampleCount)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: self.playbackFormat, frameCapacity: frameCount),
                  let floatChannel = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = frameCount

            data.withUnsafeBytes { rawBufferPointer in
                guard let int16Ptr = rawBufferPointer.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0..<Int(frameCount) {
                    floatChannel[i] = Float(int16Ptr[i]) / 32768.0
                }
            }

            self.bufferLock.lock()
            self.activeScheduledBuffers += 1
            self.bufferLock.unlock()

            DispatchQueue.main.async {
                self.isPlayingOutput = true
            }

            self.playerNode.scheduleBuffer(buffer) { [weak self] in
                guard let self = self else { return }
                self.bufferLock.lock()
                self.activeScheduledBuffers = max(0, self.activeScheduledBuffers - 1)
                let stillActive = self.activeScheduledBuffers > 0
                self.bufferLock.unlock()

                if !stillActive {
                    DispatchQueue.main.async {
                        self.isPlayingOutput = false
                    }
                }
            }
        }
    }

    // MARK: - 3. Zero-Silence Fallback Speech Synthesizer

    func speakUtteranceFallback(_ text: String) {
        fallbackSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        if let voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Evan") ??
                       AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Ava") ??
                       AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0

        DispatchQueue.main.async {
            self.isPlayingOutput = true
        }

        fallbackSynthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlayingOutput = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlayingOutput = false
        }
    }

    // MARK: - 4. Seamless Natural Barge-In / Interruption

    func interruptPlaybackImmediately() {
        bufferLock.lock()
        pendingPlaybackData = Data()
        activeScheduledBuffers = 0
        bufferLock.unlock()

        playerNode.stop()
        playerNode.play()
        fallbackSynthesizer.stopSpeaking(at: .immediate)

        DispatchQueue.main.async {
            self.isPlayingOutput = false
        }
    }

    func toggleMute() {
        isMuted.toggle()
        AcousticEarcons.shared.play(isMuted ? .micMuted : .micUnmuted)
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
        let normalized = min(1.0, max(0.0, rms * 9.0))
        DispatchQueue.main.async {
            self.inputLevel = normalized
        }
    }
}
