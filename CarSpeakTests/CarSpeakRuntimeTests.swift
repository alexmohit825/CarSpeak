import XCTest
import AVFoundation
@testable import CarSpeak

final class CarSpeakRuntimeTests: XCTestCase {

    func testCabinAudioEngineFormatAndPlaybackInSimulator() throws {
        let engine = CabinAudioEngine()
        XCTAssertEqual(engine.playbackFormat.sampleRate, 24000)
        XCTAssertEqual(engine.playbackFormat.channelCount, 1)
        XCTAssertEqual(engine.playbackFormat.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(engine.playbackFormat.isInterleaved)

        // Generate 200ms of 24kHz 16-bit PCM sine wave (9600 bytes) and enqueue + flush
        let sampleCount = 4800
        var pcmData = Data(count: sampleCount * 2)
        pcmData.withUnsafeMutableBytes { raw in
            guard let ptr = raw.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<sampleCount {
                let sample = sin(2.0 * Double.pi * 440.0 * Double(i) / 24000.0) * 8000.0
                ptr[i] = Int16(sample)
            }
        }

        let expectation = XCTestExpectation(description: "Playback state updates cleanly without crash")
        engine.enqueueLiveOutputPCM24k(pcmData)
        engine.flushPlaybackBuffer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            engine.interruptPlaybackImmediately()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
    }

    func testLiveGeminiWebSocketRealtimeAudioRoundTripInSimulator() async throws {
        // 1. Fetch live session credentials and setupPayload from Cloudflare Worker
        let configURL = URL(string: "https://carspeak-api.mohalex.workers.dev/api/live-session")!
        var req = URLRequest(url: configURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["persona": "executive"])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let httpResp = try XCTUnwrap(resp as? HTTPURLResponse)
        XCTAssertEqual(httpResp.statusCode, 200, "Worker /api/live-session must return HTTP 200")

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wsUrlString = try XCTUnwrap(json["wsUrl"] as? String)
        let wsURL = try XCTUnwrap(URL(string: wsUrlString))
        let setupPayload = try XCTUnwrap(json["setupPayload"] as? [String: Any])

        // 2. Open WebSocket to Gemini Live from inside iOS Simulator
        let session = URLSession(configuration: .default)
        let ws = session.webSocketTask(with: wsURL)
        ws.resume()
        defer { ws.cancel(with: .normalClosure, reason: nil) }

        let setupBytes = try JSONSerialization.data(withJSONObject: setupPayload)
        let setupStr = try XCTUnwrap(String(data: setupBytes, encoding: .utf8))
        try await ws.send(.string(setupStr))

        // 3. Wait for setupComplete
        var gotSetupComplete = false
        for _ in 0..<10 {
            let msg = try await ws.receive()
            let text: String? = switch msg {
            case .string(let s): s
            case .data(let d): String(data: d, encoding: .utf8)
            @unknown default: nil
            }
            if let text = text,
               let msgData = text.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
               obj["setupComplete"] != nil {
                gotSetupComplete = true
                break
            }
        }
        XCTAssertTrue(gotSetupComplete, "Gemini Live must return setupComplete in Simulator runtime")

        // 4. Stream 3200 bytes (100ms) of 16kHz PCM audio via realtimeInput.audio
        let pcm16Chunk = Data(count: 3200)
        let audioFrame: [String: Any] = [
            "realtimeInput": [
                "audio": [
                    "data": pcm16Chunk.base64EncodedString(),
                    "mimeType": "audio/pcm;rate=16000"
                ]
            ]
        ]
        let audioBytes = try JSONSerialization.data(withJSONObject: audioFrame)
        let audioStr = try XCTUnwrap(String(data: audioBytes, encoding: .utf8))
        try await ws.send(.string(audioStr))

        // 5. Trigger a spoken reply and verify > 5000 bytes of 24kHz PCM audio return
        let turnFrame: [String: Any] = [
            "clientContent": [
                "turns": [
                    ["role": "user", "parts": [["text": "Say 'Simulator audio check passed' in four words."]]]
                ],
                "turnComplete": true
            ]
        ]
        let turnBytes = try JSONSerialization.data(withJSONObject: turnFrame)
        let turnStr = try XCTUnwrap(String(data: turnBytes, encoding: .utf8))
        try await ws.send(.string(turnStr))

        var receivedAudioBytes = 0
        var sawTurnComplete = false
        for _ in 0..<40 {
            let msg = try await ws.receive()
            let text: String? = switch msg {
            case .string(let s): s
            case .data(let d): String(data: d, encoding: .utf8)
            @unknown default: nil
            }
            guard let text = text,
                  let msgData = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
                  let serverContent = obj["serverContent"] as? [String: Any] else { continue }

            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for p in parts {
                    if let inline = p["inlineData"] as? [String: Any],
                       let b64 = inline["data"] as? String,
                       let chunk = Data(base64Encoded: b64) {
                        receivedAudioBytes += chunk.count
                    }
                }
            }
            if let tc = serverContent["turnComplete"] as? Bool, tc {
                sawTurnComplete = true
                break
            }
        }

        XCTAssertTrue(sawTurnComplete, "Gemini Live must complete turn")
        XCTAssertGreaterThan(receivedAudioBytes, 5000, "Gemini Live must stream back 24kHz PCM audio")
    }

    func testOutboxRingBufferDrain() {
        let ring = OutboxRingBuffer(maxFrames: 3)
        XCTAssertTrue(ring.enqueue(pcmData: Data([1])))
        XCTAssertTrue(ring.enqueue(pcmData: Data([2])))
        XCTAssertTrue(ring.enqueue(pcmData: Data([3])))
        XCTAssertEqual(ring.pendingCount, 3)

        // Adding a 4th drops the oldest (1)
        _ = ring.enqueue(pcmData: Data([4]))
        let drained = ring.drainAll()
        XCTAssertEqual(drained, [Data([2]), Data([3]), Data([4])])
        XCTAssertEqual(ring.pendingCount, 0)
    }
}
