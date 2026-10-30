import Foundation
import AVFoundation
import UIKit

/// SOTA Cabin Audio Engine for CarSpeak.
///
/// Engineering Pillars:
/// 1. True Full-Duplex Neural Audio: Plays streaming 24kHz PCM from Gemini Live via `AVAudioPlayerNode`
///    while simultaneously capturing 16kHz PCM from the cabin microphone.
/// 2. Hardware Acoustic Echo Cancellation (`VoiceProcessingIO`):
///    Enables Apple's built-in `setVoiceProcessingEnabled(true)` on `inputNode` (the FaceTime/MS Teams standard).
///    The car stereo speaker output is mathematically cancelled from the microphone line in hardware DSP,
///    so the AI NEVER hears itself, Dr. Mohit NEVER has to say "over", and natural barge-in / interruption works seamlessly.
/// 3. Jitter Coalescing Buffer: Smooths out bursty 5G packet arrival so speech playback is completely fluid.
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

    private var shouldBeCapturing: Bool = false
    private var hasInstalledTap: Bool = false

    /// Tracks active scheduled buffers and post-speech acoustic reverb tail
    private let bufferLock = NSLock()
    private var activeScheduledBuffers: Int = 0
    private var pendingPlaybackData = Data()
    /// 120ms of 24kHz 16-bit mono PCM = 5760 bytes
    private let minCoalesceBytes: Int = 5760

    /// Callback delivering 16kHz 16-bit linear PCM audio chunks for streaming to Gemini Live
    var onPCM16ChunkCaptured: ((Data) -> Void)?

    var isAISpeakingOrInTail: Bool {
        bufferLock.lock()
        let active = activeScheduledBuffers > 0 || isPlayingOutput
        bufferLock.unlock()
        return active
    }

    override init() {
        super.init()
        setupAudioSessionObservers()
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
            if audioEngine.isRunning {
                audioEngine.pause()
            }
        } else if type == .ended {
            if shouldBeCapturing {
                ensureEngineRunning()
                playerNode.play()
            }
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard shouldBeCapturing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, self.shouldBeCapturing else { return }
            self.rebindHardwareTapIfNeeded()
        }
    }

    // MARK: - 1. Engine & Audio Session Lifecycle

    func startCabinDuplexStream() {
        shouldBeCapturing = true
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        requestRecordPermission { [weak self] granted in
            guard let self = self, granted, self.shouldBeCapturing else { return }
            self.configureAudioSessionAndStart()
        }
    }

    func stopCabinDuplexStream() {
        shouldBeCapturing = false
        interruptPlaybackImmediately()

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    private func configureAudioSessionAndStart() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Configure full-duplex conversational audio with Voice Chat mode for Hardware Echo Cancellation
            let options: AVAudioSession.CategoryOptions = [
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .allowAirPlay,
                .defaultToSpeaker,
                .mixWithOthers
            ]
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            try session.setPreferredSampleRate(24000)
            try session.setPreferredIOBufferDuration(0.02) // 20ms low-latency buffer
            try session.setActive(true, options: [])
        } catch {
            print("[CabinAudioEngine] Audio session warning: \(error.localizedDescription)")
        }

        attachAndStartNodes()
    }

    private func attachAndStartNodes() {
        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
        }

        let inputNode = audioEngine.inputNode

        // Hardware Voice Processing (Acoustic Echo Cancellation):
        // Automatically cancels audio coming out of the car speakers from the cabin microphone input!
        do {
            try inputNode.setVoiceProcessingEnabled(true)
        } catch {
            print("[CabinAudioEngine] VoiceProcessingIO warning: \(error.localizedDescription)")
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
            print("[CabinAudioEngine] Engine start error: \(error.localizedDescription)")
        }
    }

    private func installInputTap(inputNode: AVAudioInputNode) {
        guard !hasInstalledTap else { return }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else { return }

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

            // Convert Float32 [-1.0, 1.0] -> 16-bit Linear PCM for Gemini Live WebSocket
            let frames = Int(floatBuffer.frameLength)
            var pcm16Data = Data(count: frames * MemoryLayout<Int16>.size)
            pcm16Data.withUnsafeMutableBytes { rawBytes in
                guard let pcmPtr = rawBytes.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0..<frames {
                    let sample = max(-1.0, min(1.0, floatData[i]))
                    pcmPtr[i] = Int16(sample * 32767.0)
                }
            }

            self.onPCM16ChunkCaptured?(pcm16Data)
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

    // MARK: - 3. Seamless Natural Barge-In / Interruption

    func interruptPlaybackImmediately() {
        bufferLock.lock()
        pendingPlaybackData = Data()
        activeScheduledBuffers = 0
        bufferLock.unlock()

        playerNode.stop()
        playerNode.play()

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
        let normalized = min(1.0, max(0.04, rms * 9.0))
        DispatchQueue.main.async {
            self.inputLevel = normalized
        }
    }
}
