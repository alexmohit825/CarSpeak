import SwiftUI

struct CockpitView: View {
    @ObservedObject var session = GeminiLiveSessionManager.shared
    @ObservedObject var vault = ConversationVaultClient.shared
    @ObservedObject var audio = GeminiLiveSessionManager.shared.audioEngine
    @State private var commandInput: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.07)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // 1. 5G Tower Handoff & Multipath Telemetry Banner
                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(session.isLiveSessionActive ? Color.green : Color.cyan)
                                    .frame(width: 8, height: 8)
                                Text(session.telemetry.networkInterface)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.07), in: Capsule())

                            Text("5G Outbox: 5.0s PCM16")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.cyan.opacity(0.12), in: Capsule())

                            Spacer()

                            Text("\(vault.agProjects.count) AG Apps")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.mint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.mint.opacity(0.12), in: Capsule())
                        }
                        .padding(.horizontal)

                        // 2. Active Conversation Card (Voice Switchable)
                        if let active = vault.activeConversation {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Label("ACTIVE CONVERSATION THREAD", systemImage: "bubble.left.and.bubble.right.fill")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.cyan)
                                    Spacer()
                                    Text(active.projectName ?? "General")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.cyan.opacity(0.18), in: Capsule())
                                        .foregroundStyle(.cyan)
                                }
                                Text(active.title)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                Text(active.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(red: 0.08, green: 0.10, blue: 0.14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal)
                        }

                        // 3. Giant Eyes-Free CarPlay / Cockpit Voice Orb
                        VStack(spacing: 12) {
                            Button {
                                if session.isLiveSessionActive {
                                    session.stopHandsFreeSession()
                                } else {
                                    session.startHandsFreeSession()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: session.isLiveSessionActive
                                                    ? [Color.mint, Color.teal, Color.black]
                                                    : [Color.cyan, Color.blue.opacity(0.6), Color.black],
                                                center: .center,
                                                startRadius: 12,
                                                endRadius: 85
                                            )
                                        )
                                        .frame(width: 152, height: 152)
                                        .scaleEffect(session.isLiveSessionActive ? CGFloat(1.0 + audio.inputLevel * 0.18) : 1.0)
                                        .shadow(
                                            color: (session.isLiveSessionActive ? Color.mint : Color.cyan).opacity(0.55),
                                            radius: 24
                                        )

                                    VStack(spacing: 6) {
                                        Image(systemName: session.isLiveSessionActive ? "waveform" : "mic.fill")
                                            .font(.system(size: 42, weight: .bold))
                                            .foregroundStyle(.white)
                                        Text(session.isLiveSessionActive ? "LIVE ON CARPLAY" : "TAP OR ASK SIRI")
                                            .font(.caption2.weight(.heavy))
                                            .foregroundStyle(.white.opacity(0.92))
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Text(session.connectionStatusText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            // Steering Wheel / Cabin Quick Controls
                            HStack(spacing: 12) {
                                Button {
                                    audio.toggleMute()
                                } label: {
                                    Label(audio.isMuted ? "Unmute" : "Mute Mic", systemImage: audio.isMuted ? "mic.slash.fill" : "mic.fill")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(audio.isMuted ? Color.red.opacity(0.25) : Color.white.opacity(0.08), in: Capsule())
                                        .foregroundStyle(audio.isMuted ? .red : .white)
                                }

                                Button {
                                    audio.interruptPlaybackImmediately()
                                } label: {
                                    Label("Interrupt (>>)", systemImage: "forward.end.fill")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(Color.white.opacity(0.08), in: Capsule())
                                        .foregroundStyle(.white)
                                }

                                Button {
                                    session.cyclePersonaMode()
                                } label: {
                                    Label(session.currentPersona.shortLabel, systemImage: "person.wave.2.fill")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(Color.cyan.opacity(0.2), in: Capsule())
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }
                        .padding(.vertical, 6)

                        // 4. Quick Voice Thread-Switching Presets
                        VStack(alignment: .leading, spacing: 8) {
                            Text("VOICE ARCHIVE & AG PROJECT COMMANDS")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    voicePresetButton("Switch to DuralGuard thread")
                                    voicePresetButton("Switch to Radix & PJKPredict")
                                    voicePresetButton("Switch to MDEsq & CPTArmor")
                                    voicePresetButton("Where did we leave off on Spine-Measure?")
                                    voicePresetButton("List my archived conversations")
                                }
                                .padding(.horizontal)
                            }
                        }

                        // 5. Live Transcript Feed
                        if let turns = vault.activeConversation?.turns, !turns.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(turns.suffix(6)) { turn in
                                    VStack(alignment: turn.role == "user" ? .trailing : .leading, spacing: 4) {
                                        Text(turn.role == "user" ? "Dr. Mohit" : "CarSpeak")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(turn.role == "user" ? .secondary : .cyan)
                                        Text(turn.text)
                                            .font(.subheadline)
                                            .foregroundStyle(.white)
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill(turn.role == "user"
                                                          ? Color.white.opacity(0.08)
                                                          : Color.cyan.opacity(0.14))
                                            )
                                    }
                                    .frame(maxWidth: .infinity, alignment: turn.role == "user" ? .trailing : .leading)
                                }
                            }
                            .padding(.horizontal)
                        }

                        // 6. Voice / Text Command Bar
                        HStack(spacing: 8) {
                            TextField("Say or type command (e.g. 'Switch to DuralGuard')...", text: $commandInput)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)

                            Button {
                                let cmd = commandInput
                                commandInput = ""
                                Task {
                                    await session.sendVoiceOrTextCommand(cmd)
                                }
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("CarSpeak Cockpit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func voicePresetButton(_ command: String) -> some View {
        Button {
            Task {
                await session.sendVoiceOrTextCommand(command)
            }
        } label: {
            Text("\"\(command)\"")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                .foregroundStyle(.white)
        }
    }
}
