import Foundation
import AVFoundation

/// Hardware-accelerated CarPlay & In-Cabin Audio Engine.
/// Uses `AVAudioSession.Mode.voiceChat` with `.allowBluetooth` and `.allowBluetoothA2DP`
/// to route seamlessly through the vehicle's factory cabin microphone array and speakers,
/// with hardware Acoustic Echo Cancellation (AEC) so the mic never re-triggers on AI speech.
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

    private let speechSynthesizer = AVSpeechSynthesizer()
    var onPCM16ChunkCaptured: ((Data) -> Void)?

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    func configureCarPlayAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .duckOthers]
            )
            try session.setPreferredSampleRate(16000)
            try session.setPreferredIOBufferDuration(0.064)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[CabinAudioEngine] AudioSession configuration warning: \(error.localizedDescription)")
        }
    }

    func startCabinDuplexStream() {
        guard !isCapturing else { return }
        configureCarPlayAudioSession()

        let inputNode = audioEngine.inputNode
        if #available(iOS 13.0, *) {
            try? inputNode.setVoiceProcessingEnabled(true)
        }

        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        }

        let hwFormat = inputNode.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 else { return }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        let converter = AVAudioConverter(from: hwFormat, to: targetFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self, !self.isMuted else { return }
            self.computeRMS(buffer: buffer)

            guard let converter = converter else { return }
            let ratio = 16000.0 / hwFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

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
            converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)

            if error == nil, pcmBuffer.frameLength > 0, let int16Ptr = pcmBuffer.int16ChannelData {
                let byteCount = Int(pcmBuffer.frameLength) * MemoryLayout<Int16>.size
                let data = Data(bytes: int16Ptr[0], count: byteCount)
                self.onPCM16ChunkCaptured?(data)
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
        guard isCapturing else { return }
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
    func enqueueLiveOutputPCM24k(_ data: Data) {
        guard data.count >= 2, isCapturing else { return }
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
        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlayingOutput = false
            }
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// Immediately clears playback queue when Dr. Mohit barges in or presses Next Track (>>) on steering wheel.
    func interruptPlaybackImmediately() {
        playerNode.stop()
        if isCapturing {
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
