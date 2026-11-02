import Foundation
import AVFoundation
import AudioToolbox

/// Generates subtle, eyes-free cabin earcons so Dr. Mohit has instant auditory confirmation
/// of session start, "over" turn completion, thread switches, and mic states while keeping eyes on the road.
final class AcousticEarcons {
    static let shared = AcousticEarcons()

    enum EarconType {
        case sessionReady       // Ascending warm chime (Ready to talk)
        case turnSent           // Crisp acknowledgment chirp (Turn sent via "over" or tap)
        case handoffHealed      // Subtle soft pulse (5G tower handoff seamless)
        case threadSwitched     // Crisp double-chime confirming conversation switch
        case micMuted           // Descending soft tone
        case micUnmuted         // Ascending soft tone
    }

    func play(_ type: EarconType) {
        switch type {
        case .sessionReady:
            AudioServicesPlaySystemSound(1113) // Begin record chime
        case .turnSent:
            AudioServicesPlaySystemSound(1114) // Crisp acknowledgment chirp
        case .handoffHealed:
            AudioServicesPlaySystemSound(1057) // Subtle tink
        case .threadSwitched:
            AudioServicesPlaySystemSound(1054) // Navigation/switch chime
        case .micMuted:
            AudioServicesPlaySystemSound(1114)
        case .micUnmuted:
            AudioServicesPlaySystemSound(1113)
        }
    }
}
