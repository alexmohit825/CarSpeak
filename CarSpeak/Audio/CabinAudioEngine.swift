import Foundation
import AVFoundation

/// Hardware-accelerated CarPlay & In-Cabin Audio Engine.
/// Routes seamlessly through Apple CarPlay (`.carAudio`), Bluetooth A2DP/HFP, or iPhone speaker,
/// with automatic post-Siri interruption recovery and Float32 resampling.
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
    private var watchdogTimer: Timer?
    var onPCM16ChunkCaptured: ((Data) -> Void)?

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
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended, shouldBeCapturing {
            // Siri or system alert finished — immediately reclaim CarPlay audio session & restart engine
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.restartEngineAfterSiriOrRouteChange()
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard shouldBeCapturing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.shouldBeCapturing, !self.audioEngine.isRunning else { return }
            self.restartEngineAfterSiriOrRouteChange()
        }
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

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self = self, granted else { return }
            DispatchQueue.main.async {
                self.configureAndStartEngineInternal()
                self.startPostSiriWatchdog()
            }
        }
    }

    private func startPostSiriWatchdog() {
        watchdogTimer?.invalidate()
        // Re-verify engine is running 0.9s and 2.0s after launch in case Siri was dismissing during startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self = self, self.shouldBeCapturing else { return }
            if !self.audioEngine.isRunning || !self.playerNode.isPlaying {
                self.restartEngineAfterSiriOrRouteChange()
            }
        }
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.shouldBeCapturing else { return }
            if !self.audioEngine.isRunning {
                self.restartEngineAfterSiriOrRouteChange()
            }
        }
    }

    func restartEngineAfterSiriOrRouteChange() {
        guard shouldBeCapturing else { return }
        configureAndStartEngineInternal()
    }

    private func configureAndStartEngineInternal() {
        configureCarPlayAudioSession()

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
        }
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        if recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 {
            let converter = AVAudioConverter(from: recordingFormat, to: float16kFormat)
            let targetFormat = float16kFormat

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
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            playerNode.play()
            DispatchQueue.main.async {
                self.isCapturing = true
            }
            AcousticEarcons.shared.play(.sessionReady)
        } catch {
            print("[CabinAudioEngine] Start error: \(error.localizedDescription)")
        }
    }

    func stopCabinDuplexStream() {
        shouldBeCapturing = false
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
        DispatchQueue.main.async {
            self.isCapturing = false
            self.inputLevel = 0.0
        }
    }

    func toggleMute() {
        isMuted.toggle()
        AcousticEarcons.shared.play(isMuted ? .micMuted : .micUnmuted)
    }

    /// Converts 24kHz PCM16 little-endian audio chunks from Gemini 3.8 Live into Float32 buffers for iOS AVAudioPlayerNode.
    /// Automatically wakes the playback engine if it was paused by Siri or a route change.
    func enqueueLiveOutputPCM24k(_ data: Data) {
        guard data.count >= 2 else { return }

        if !audioEngine.isRunning {
            configureAndStartEngineInternal()
        }

        let sampleCount = data.count / MemoryLayout<Int16>.size
        let frameCount = AVAudioFrameCount(sampleCount)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount),
              let floatChannel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawBufferPointer in
            guard let int16Ptr = rawBufferPointer.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<sampleCount {
                let sample = Int16(littleEndian: int16Ptr[i])
                floatChannel[i] = Float(sample) / 32768.0
            }
        }

        DispatchQueue.main.async {
            self.isPlayingOutput = true
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlayingOutput = false
            }
        }
    }

    /// Immediately clears playback queue when Dr. Mohit barges in or presses Next Track (>>) on steering wheel.
    func interruptPlaybackImmediately() {
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
        DispatchQueue.main.async {
            self.isPlayingOutput = false
        }
    }
}
