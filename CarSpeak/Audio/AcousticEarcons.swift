import Foundation
import AVFoundation
import AudioToolbox

/// Generates subtle, eyes-free cabin earcons so Dr. Mohit has instant auditory confirmation
/// of session start, 5G handoff healing, conversation thread switches, and mic mute state.
final class AcousticEarcons {
    static let shared = AcousticEarcons()

    enum EarconType {
        case sessionReady       // Ascending warm chime
        case handoffHealed      // Subtle soft pulse
        case threadSwitched     // Crisp double-chime confirming conversation switch
        case micMuted           // Descending soft tone
        case micUnmuted         // Ascending soft tone
    }

    func play(_ type: EarconType) {
        switch type {
        case .sessionReady:
            AudioServicesPlaySystemSound(1113) // Begin record chime
        case .handoffHealed:
            AudioServicesPlaySystemSound(1057) // Subtle tink
        case .threadSwitched:
            AudioServicesPlaySystemSound(1054) // Navigation/switch chime
        case .micMuted:
            AudioServicesPlaySystemSound(1114) // Stop record tone
        case .micUnmuted:
            AudioServicesPlaySystemSound(1113)
        }
    }
}
