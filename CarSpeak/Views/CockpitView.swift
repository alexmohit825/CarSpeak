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
                        telemetryHeaderView
                        activeThreadCardView
                        voiceOrbSectionView
                        voicePresetsSectionView
                        transcriptSectionView
                        commandComposerView
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("CarSpeak Cockpit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var telemetryHeaderView: some View {
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
    }

    @ViewBuilder
    private var activeThreadCardView: some View {
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
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var voiceOrbSectionView: some View {
        let orbScale: CGFloat = session.isLiveSessionActive ? CGFloat(1.0 + Double(audio.inputLevel) * 0.18) : 1.0
        let orbColors: [Color] = session.isLiveSessionActive
            ? [Color.mint, Color.teal, Color.black]
            : [Color.cyan, Color.blue.opacity(0.6), Color.black]
        let shadowColor: Color = (session.isLiveSessionActive ? Color.mint : Color.cyan).opacity(0.55)

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
                                colors: orbColors,
                                center: .center,
                                startRadius: 12,
                                endRadius: 85
                            )
                        )
                        .frame(width: 152, height: 152)
                        .scaleEffect(orbScale)
                        .shadow(color: shadowColor, radius: 24)

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

            cabinQuickControlsRow
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var cabinQuickControlsRow: some View {
        let muteBg = audio.isMuted ? Color.red.opacity(0.25) : Color.white.opacity(0.08)
        let muteFg = audio.isMuted ? Color.red : Color.white

        HStack(spacing: 12) {
            Button {
                audio.toggleMute()
            } label: {
                Label(audio.isMuted ? "Unmute" : "Mute Mic", systemImage: audio.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(muteBg, in: Capsule())
                    .foregroundStyle(muteFg)
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

    @ViewBuilder
    private var voicePresetsSectionView: some View {
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
    }

    @ViewBuilder
    private var transcriptSectionView: some View {
        if let turns = vault.activeConversation?.turns, !turns.isEmpty {
            let recentTurns = Array(turns.suffix(6))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(recentTurns) { turn in
                    turnBubbleView(turn)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func turnBubbleView(_ turn: TranscriptTurn) -> some View {
        let isUser = (turn.role == "user")
        let bubbleBg = isUser ? Color.white.opacity(0.08) : Color.cyan.opacity(0.14)
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(isUser ? "Dr. Mohit" : "CarSpeak")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isUser ? Color.secondary : Color.cyan)
            Text(turn.text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(bubbleBg)
                )
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private var commandComposerView: some View {
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
