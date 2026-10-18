import Foundation
import MediaPlayer
import UIKit

/// Integrates CarSpeak with the CarPlay "Now Playing" Dashboard and Physical Steering Wheel Buttons.
/// Works 100% automatically whenever CarSpeak is launched via Siri ("Hey Siri, start CarSpeak")
/// or from the CarPlay screen.
final class SteeringWheelController {
    static let shared = SteeringWheelController()

    private var isConfigured = false

    func configureRemoteCommands() {
        guard !isConfigured else { return }
        isConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()

        // Steering Wheel Play/Pause -> Toggle Cabin Mic Mute/Unmute
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            GeminiLiveSessionManager.shared.audioEngine.toggleMute()
            self.updateNowPlayingDashboard()
            return .success
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            if !GeminiLiveSessionManager.shared.isLiveSessionActive {
                GeminiLiveSessionManager.shared.startHandsFreeSession()
            } else if GeminiLiveSessionManager.shared.audioEngine.isMuted {
                GeminiLiveSessionManager.shared.audioEngine.toggleMute()
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

        // Steering Wheel Next Track (>>) -> Immediate Barge-In / Interrupt AI Response
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

    func updateNowPlayingDashboard() {
        let manager = GeminiLiveSessionManager.shared
        let activeConv = ConversationVaultClient.shared.activeConversation

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = activeConv?.title ?? "CarSpeak Hands-Free AI"
        info[MPMediaItemPropertyArtist] = "CarSpeak • \(manager.currentPersona.displayName)"
        info[MPMediaItemPropertyAlbumTitle] = "AG Project: \(activeConv?.projectName ?? "All 56 Projects") • 5G Resilient"
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = manager.audioEngine.isMuted ? 0.0 : 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
