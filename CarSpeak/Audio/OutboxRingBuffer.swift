import Foundation

/// Lock-free / NSLock-protected 5-second circular PCM16 audio outbox buffer.
/// Ensures that during a 5G tower-to-tower handoff (200-800ms packet stall or sub-second socket heal),
/// zero spoken syllables from the car cabin microphone are dropped.
final class OutboxRingBuffer {
    struct AudioFrame {
        let sequenceId: UInt64
        let timestamp: TimeInterval
        let base64PCM16: String
    }

    private let lock = NSLock()
    private var buffer: [AudioFrame] = []
    private let maxFrames: Int
    private var nextSequenceId: UInt64 = 1
    private var lastAckedSequenceId: UInt64 = 0

    /// At ~10 chunks/sec (100ms per PCM16 chunk), 50 frames = 5.0 seconds of rolling speech protection.
    init(maxFrames: Int = 50) {
        self.maxFrames = maxFrames
    }

    @discardableResult
    func enqueue(pcmData: Data) -> AudioFrame {
        lock.lock()
        defer { lock.unlock() }

        let frame = AudioFrame(
            sequenceId: nextSequenceId,
            timestamp: Date().timeIntervalSince1970,
            base64PCM16: pcmData.base64EncodedString()
        )
        nextSequenceId += 1
        buffer.append(frame)
        if buffer.count > maxFrames {
            buffer.removeFirst(buffer.count - maxFrames)
        }
        return frame
    }

    func markSent(sequenceId: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if sequenceId > lastAckedSequenceId {
            lastAckedSequenceId = sequenceId
        }
        buffer.removeAll { $0.sequenceId <= lastAckedSequenceId }
    }

    /// Returns all unacknowledged frames captured during a 5G tower handoff window (up to maxAgeSeconds)
    func drainPendingFrames(maxAgeSeconds: TimeInterval = 5.0) -> [AudioFrame] {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = Date().timeIntervalSince1970 - maxAgeSeconds
        let pending = buffer.filter { $0.sequenceId > lastAckedSequenceId && $0.timestamp >= cutoff }
        return pending
    }

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}
