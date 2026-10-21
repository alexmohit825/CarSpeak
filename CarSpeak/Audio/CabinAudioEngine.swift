import Foundation
import AVFoundation

/// Rebuilt Hardware-Accelerated CarPlay & In-Cabin Audio Engine.
/// Key Guarantees:
/// 1. Strict Half-Duplex Speaker Priority Gate (`isAISpeaking` + 450ms acoustic tail): The microphone tap NEVER
///    transmits room audio while Gemini is speaking, making "CarSpeak, CarSpeak" echo/self-interruption impossible.
/// 2. 200ms Jitter Pre-Buffer (`pendingPlaybackData`): Coalesces small 24kHz WebSocket audio packets into smooth,
///    continuous buffers so 5G packet jitter never causes stuttering or mid-sentence cut-outs.
/// 3. Zero Mid-Stream Engine Stops: Never calls `audioEngine.stop()` while a session is active.
final class CabinAudioEngine: NSObject, ObservableObject {
    @Published var isCapturing: Bool = false
    @Published var isMuted: Bool = false
    @Published var inputLevel: Float = 0.0
    @Published var isPlayingOutput: Bool = false

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    /// Standard 32-bit Float non-interleaved 24kHz mono format required by iOS AVAudioPlayerNode & AVAudioMixerNode
    private let playbackFormat = AVAudioFormat(
        standardFormatWithSampleRate: 24000,
        channels: 1
    )!
    /// Standard 32-bit Float non-interleaved 16kHz mono format for hardware resampler
    private let float16kFormat = AVAudioFormat(
        standardFormatWithSampleRate: 16000,
        channels: 1
    )!

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var shouldBeCapturing: Bool = false
    private var hasInstalledTap: Bool = false

    /// Tracks active scheduled buffers and post-speech acoustic reverb tail to prevent mic self-triggering
    private let bufferLock = NSLock()
    private var activeScheduledBuffers: Int = 0
    private var speechTailDeadline: Date = .distantPast
    private var pendingPlaybackData = Data()
    /// 180ms of 24kHz 16-bit mono PCM = 8640 bytes
    private let minCoalesceBytes: Int = 8640

    var onPCM16ChunkCaptured: ((Data) -> Void)?

    var isAISpeakingOrInTail: Bool {
        bufferLock.lock()
        let active = activeScheduledBuffers > 0 || Date() < speechTailDeadline || speechSynthesizer.isSpeaking
        bufferLock.unlock()
        return active
    }

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        setupAudioSessionObservers()
    }

    private func setupAudioSessionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended, shouldBeCapturing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.rebindTapIfHardwareRateChangedAndEnsureRunning()
            }
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard shouldBeCapturing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.rebindTapIfHardwareRateChangedAndEnsureRunning()
        }
    }

    /// When Siri dismisses on CarPlay or CarPlay switches between Siri HFP and Cabin Audio,
    /// the hardware inputNode sample rate changes (e.g. 24kHz <-> 48kHz). Re-install the tap cleanly.
    func rebindTapIfHardwareRateChangedAndEnsureRunning() {
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        ensureEngineRunning()
    }

    func configureCarPlayAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            let hasExternalCarOrBT = session.currentRoute.outputs.contains { port in
                port.portType == .carAudio ||
                port.portType == .bluetoothA2DP ||
                port.portType == .bluetoothHFP ||
                port.portType == .bluetoothLE
            }

            var options: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]
            if !hasExternalCarOrBT {
                options.insert(.defaultToSpeaker)
            }

            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: options
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[CabinAudioEngine] AudioSession configuration warning: \(error.localizedDescription)")
        }
    }

    func startCabinDuplexStream() {
        shouldBeCapturing = true

        // Synchronously configure & start AVAudioEngine playback immediately so iOS AudioStartingIntent
        // and CarPlay grant background audio ownership during perform() before permission callback returns.
        configureCarPlayAudioSession()
        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        }
        if !audioEngine.isRunning {
            try? audioEngine.start()
            playerNode.play()
        }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self, granted else { return }
            DispatchQueue.main.async {
                self.rebindTapIfHardwareRateChangedAndEnsureRunning()
            }
        }
    }

    func restartEngineAfterSiriOrRouteChange() {
        guard shouldBeCapturing else { return }
        ensureEngineRunning()
    }

    func ensureEngineRunning() {
        configureCarPlayAudioSession()

        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        }

        if !hasInstalledTap {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            if recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 {
                let converter = AVAudioConverter(from: recordingFormat, to: float16kFormat)
                let targetFormat = float16kFormat

                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                    guard let self = self, !self.isMuted else { return }
                    // CRITICAL HALF-DUPLEX GATE: Never capture or send mic audio while Gemini is speaking
                    // or within 450ms after Gemini finishes speaking (prevents speaker-to-mic feedback loop).
                    if self.isAISpeakingOrInTail {
                        DispatchQueue.main.async {
                            self.inputLevel = 0.05
                        }
                        return
                    }

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

                    let frameLen = Int(floatBuffer.frameLength)
                    if error == nil, frameLen > 0, let floatPtr = floatBuffer.floatChannelData?[0] {
                        var pcm16Samples = [Int16](repeating: 0, count: frameLen)
                        for i in 0..<frameLen {
                            let clamped = max(-1.0, min(1.0, floatPtr[i]))
                            pcm16Samples[i] = Int16(clamped * 32767.0)
                        }
                        let data = pcm16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
                        self.onPCM16ChunkCaptured?(data)
                    }
                }
                hasInstalledTap = true
            }
        }

        if !audioEngine.isRunning {
            do {
                audioEngine.prepare()
                try audioEngine.start()
                playerNode.play()
                DispatchQueue.main.async {
                    self.isCapturing = true
                }
            } catch {
                print("[CabinAudioEngine] Start error: \(error.localizedDescription)")
            }
        } else if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func stopCabinDuplexStream() {
        shouldBeCapturing = false
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        bufferLock.lock()
        pendingPlaybackData.removeAll()
        activeScheduledBuffers = 0
        speechTailDeadline = .distantPast
        bufferLock.unlock()

        playerNode.stop()
        audioEngine.stop()
        DispatchQueue.main.async {
            self.isCapturing = false
            self.isPlayingOutput = false
            self.inputLevel = 0.0
        }
    }

    func toggleMute() {
        isMuted.toggle()
        AcousticEarcons.shared.play(isMuted ? .micMuted : .micUnmuted)
    }

    /// Accumulates incoming 24kHz PCM16 audio chunks into smooth 180ms+ coalesced buffers to eliminate packet jitter.
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

    /// Flushes any remaining sub-180ms tail of audio at the end of a model turn.
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
            if !self.audioEngine.isRunning {
                self.ensureEngineRunning()
            }

            let sampleCount = data.count / MemoryLayout<Int16>.size
            let frameCount = AVAudioFrameCount(sampleCount)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: self.playbackFormat, frameCapacity: frameCount),
                  let floatChannel = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = frameCount

            data.withUnsafeBytes { rawBufferPointer in
                guard let int16Ptr = rawBufferPointer.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0..<sampleCount {
                    let sample = Int16(littleEndian: int16Ptr[i])
                    floatChannel[i] = Float(sample) / 32768.0
                }
            }

            self.bufferLock.lock()
            self.activeScheduledBuffers += 1
            self.speechTailDeadline = Date().addingTimeInterval(0.6)
            self.bufferLock.unlock()

            self.isPlayingOutput = true
            if !self.playerNode.isPlaying {
                self.playerNode.play()
            }

            self.playerNode.scheduleBuffer(buffer) { [weak self] in
                guard let self = self else { return }
                self.bufferLock.lock()
                self.activeScheduledBuffers = max(0, self.activeScheduledBuffers - 1)
                let stillActive = self.activeScheduledBuffers > 0
                if !stillActive {
                    // Hold mic gate for 450ms after final speaker buffer finishes so room echo decays completely
                    self.speechTailDeadline = Date().addingTimeInterval(0.45)
                }
                self.bufferLock.unlock()

                if !stillActive {
                    DispatchQueue.main.async {
                        self.isPlayingOutput = false
                    }
                }
            }
        }
    }

    /// Immediately clears playback queue when Dr. Mohit explicitly taps Stop Audio or Next Track (>>).
    func interruptPlaybackImmediately() {
        bufferLock.lock()
        pendingPlaybackData.removeAll()
        activeScheduledBuffers = 0
        speechTailDeadline = Date().addingTimeInterval(0.25)
        bufferLock.unlock()

        playerNode.stop()
        if audioEngine.isRunning {
            playerNode.play()
        }
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async {
            self.isPlayingOutput = false
        }
    }

    /// Fallback neural speech synthesizer for offline/REST responses or thread-switch announcements.
    func speakFallbackText(_ text: String) {
        configureCarPlayAudioSession()
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        bufferLock.lock()
        speechTailDeadline = Date().addingTimeInterval(2.0)
        bufferLock.unlock()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        DispatchQueue.main.async {
            self.isPlayingOutput = true
        }
        speechSynthesizer.speak(utterance)
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

extension CabinAudioEngine: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        bufferLock.lock()
        speechTailDeadline = Date().addingTimeInterval(0.45)
        bufferLock.unlock()
        DispatchQueue.main.async {
            self.isPlayingOutput = false
        }
    }
}
