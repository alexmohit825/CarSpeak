import Foundation
import MediaPlayer
import UIKit

/// Integrates CarSpeak with the CarPlay "Now Playing" Dashboard (`CPNowPlayingTemplate`)
/// and Physical Steering Wheel Buttons, matching the proven `Hands-Free Lingo` MediaPlayer setup.
final class SteeringWheelController {
    static let shared = SteeringWheelController()

    private var isConfigured = false

    func configureRemoteCommands() {
        guard !isConfigured else { return }
        isConfigured = true

        DispatchQueue.main.async {
            UIApplication.shared.beginReceivingRemoteControlEvents()
        }

        let commandCenter = MPRemoteCommandCenter.shared()

        // Steering Wheel Play/Pause -> Toggle Cabin Mic Mute/Unmute or Start Loop
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            if !GeminiLiveSessionManager.shared.isLiveSessionActive {
                GeminiLiveSessionManager.shared.startHandsFreeSession(forceRestartAudio: true)
            } else {
                GeminiLiveSessionManager.shared.audioEngine.toggleMute()
            }
            self.updateNowPlayingDashboard()
            return .success
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            if !GeminiLiveSessionManager.shared.isLiveSessionActive {
                GeminiLiveSessionManager.shared.startHandsFreeSession(forceRestartAudio: true)
            } else if GeminiLiveSessionManager.shared.audioEngine.isMuted {
                GeminiLiveSessionManager.shared.audioEngine.toggleMute()
            } else {
                GeminiLiveSessionManager.shared.startHandsFreeSession(forceRestartAudio: true)
            }
            self.updateNowPlayingDashboard()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            GeminiLiveSessionManager.shared.audioEngine.toggleMute()
            self.updateNowPlayingDashboard()
            return .success
        }

        // Steering Wheel Next Track (>>) -> Immediate Skip / Interrupt AI Response & Listen Now
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            GeminiLiveSessionManager.shared.audioEngine.interruptPlaybackImmediately()
            self.updateNowPlayingDashboard()
            return .success
        }

        // Steering Wheel Previous Track (<<) -> Cycle Persona Mode (Executive -> Surgical -> Architect -> Roadmap)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            GeminiLiveSessionManager.shared.cyclePersonaMode()
            self.updateNowPlayingDashboard()
            return .success
        }

        updateNowPlayingDashboard()
    }

    func updateNowPlayingDashboard(duration: TimeInterval = 30.0, elapsed: TimeInterval = 0.0, isSpeaking: Bool = false) {
        let manager = GeminiLiveSessionManager.shared
        let activeConv = ConversationVaultClient.shared.activeConversation

        var info: [String: Any] = [:]
        let latestText = !manager.liveModelTranscript.isEmpty
            ? String(manager.liveModelTranscript.prefix(64))
            : (activeConv?.title ?? "CarSpeak Hands-Free AI")
        info[MPMediaItemPropertyTitle] = latestText
        info[MPMediaItemPropertyArtist] = "CarSpeak • \(manager.currentPersona.displayName)"
        info[MPMediaItemPropertyAlbumTitle] = "AG Project: \(activeConv?.projectName ?? "All 56 Projects")"
        info[MPMediaItemPropertyPlaybackDuration] = max(1.0, duration)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = (isSpeaking || manager.isLiveSessionActive) && !manager.audioEngine.isMuted ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
