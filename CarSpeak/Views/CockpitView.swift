import SwiftUI

struct CockpitView: View {
    @ObservedObject var session = GeminiLiveSessionManager.shared
    @ObservedObject var vault = ConversationVaultClient.shared
    @ObservedObject var audio = GeminiLiveSessionManager.shared.audioEngine
    @ObservedObject var speech = GeminiLiveSessionManager.shared.audioEngine.speechTranscriber
    @State private var selectedProjectName: String = ""
    @State private var commandInput: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.97, green: 0.98, blue: 1.00),
                        Color(red: 0.93, green: 0.96, blue: 1.00),
                        Color(red: 1.00, green: 0.97, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerBadgeRow
                        projectDropdownCard
                        voiceOrbCard
                        liveSpokenBubbleCard
                        latestTurnCard
                        bottomComposerBar
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("CarSpeak")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !session.isLiveSessionActive {
                    session.startHandsFreeSession()
                }
            }
        }
    }

    // MARK: - 1. Clean Colorful Status Header

    @ViewBuilder
    private var headerBadgeRow: some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(session.isLiveSessionActive ? Color(red: 0.06, green: 0.73, blue: 0.51) : Color.gray)
                    .frame(width: 9, height: 9)
                Text(session.isLiveSessionActive ? "5G Continuous Co-Pilot" : "Co-Pilot Standby")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(red: 0.03, green: 0.47, blue: 0.34))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(red: 0.82, green: 0.98, blue: 0.90), in: Capsule())

            Spacer()

            Text(session.currentPersona.displayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.31, green: 0.27, blue: 0.90))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(red: 0.88, green: 0.91, blue: 1.00), in: Capsule())
        }
    }

    // MARK: - 2. Single Clean Dropdown Menu for Previous Projects

    @ViewBuilder
    private var projectDropdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE ANTIGRAVITY CONTEXT (56 PROJECTS)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color(red: 0.31, green: 0.27, blue: 0.90))

            Menu {
                Button("General Neurosurgical & Innovation Consult") {
                    selectedProjectName = ""
                }
                Divider()
                ForEach(vault.agProjects) { proj in
                    Button("\(proj.displayName) — \(proj.category)") {
                        selectedProjectName = proj.displayName
                        Task {
                            await session.sendVoiceOrTextCommand("Let's focus on \(proj.displayName). Summarize our active focus and roadmap.")
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "folder.fill.badge.gearshape")
                        .foregroundStyle(Color(red: 0.05, green: 0.65, blue: 0.91))
                    Text(selectedProjectName.isEmpty ? "Select an Antigravity Project (\(vault.agProjects.count))" : selectedProjectName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(red: 0.96, green: 0.98, blue: 1.00), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 0.05, green: 0.65, blue: 0.91).opacity(0.35), lineWidth: 1.5)
                )
            }

            if !vault.conversations.isEmpty {
                Menu {
                    ForEach(vault.conversations) { conv in
                        Button(conv.title) {
                            Task {
                                _ = await vault.switchConversation(queryOrId: conv.id)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Color(red: 0.98, green: 0.45, blue: 0.09))
                        Text(vault.activeConversation?.title ?? "Switch Saved Thread (\(vault.conversations.count))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(11)
                    .background(Color(red: 1.00, green: 0.96, blue: 0.92), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 6)
    }

    // MARK: - 3. Central Colorful Voice Orb Card

    @ViewBuilder
    private var voiceOrbCard: some View {
        let isSpeaking = audio.isPlayingOutput
        let isCapturing = session.isLiveSessionActive && !isSpeaking
        let orbScale: CGFloat = isSpeaking ? 1.06 : (isCapturing ? CGFloat(1.0 + Double(audio.inputLevel) * 0.16) : 1.0)

        let speakingGradient = LinearGradient(
            colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.31, green: 0.27, blue: 0.90)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let listeningGradient = LinearGradient(
            colors: [Color(red: 0.06, green: 0.73, blue: 0.51), Color(red: 0.05, green: 0.65, blue: 0.91)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let standbyGradient = LinearGradient(
            colors: [Color.gray, Color.secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        VStack(spacing: 18) {
            Button {
                if isSpeaking {
                    // Tap to interrupt AI speech immediately
                    audio.interruptPlaybackImmediately()
                } else if isCapturing {
                    // If Dr. Mohit has spoken text, force send turn immediately
                    if !speech.liveTranscript.isEmpty {
                        speech.forceSubmitCurrentTranscript()
                    } else {
                        session.stopHandsFreeSession()
                    }
                } else {
                    session.startHandsFreeSession()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isSpeaking ? speakingGradient : (isCapturing ? listeningGradient : standbyGradient))
                        .frame(width: 160, height: 160)
                        .scaleEffect(orbScale)
                        .shadow(
                            color: (isSpeaking
                                    ? Color(red: 0.31, green: 0.27, blue: 0.90)
                                    : (isCapturing ? Color(red: 0.06, green: 0.73, blue: 0.51) : Color.gray)).opacity(0.38),
                            radius: 24,
                            y: 10
                        )

                    VStack(spacing: 8) {
                        Image(systemName: isSpeaking ? "speaker.wave.3.fill" : (isCapturing ? "waveform" : "mic.fill"))
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)

                        Text(isSpeaking ? "TAP TO STOP" : (isCapturing ? "SAY 'OVER' OR TAP" : "TAP TO START"))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .tracking(0.5)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(session.connectionStatusText)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15))
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    audio.toggleMute()
                } label: {
                    Label(audio.isMuted ? "Unmute" : "Mute", systemImage: audio.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(red: 1.00, green: 0.93, blue: 0.84), in: Capsule())
                        .foregroundStyle(Color(red: 0.76, green: 0.25, blue: 0.05))
                }

                Button {
                    audio.interruptPlaybackImmediately()
                } label: {
                    Label("Interrupt", systemImage: "stop.circle.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(red: 1.00, green: 0.89, blue: 0.90), in: Capsule())
                        .foregroundStyle(Color(red: 0.75, green: 0.07, blue: 0.24))
                }

                Button {
                    session.cyclePersonaMode()
                } label: {
                    Label(session.currentPersona.shortLabel, systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(red: 0.88, green: 0.91, blue: 1.00), in: Capsule())
                        .foregroundStyle(Color(red: 0.22, green: 0.19, blue: 0.64))
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(session.isLiveSessionActive ? Color(red: 0.06, green: 0.73, blue: 0.51) : Color.gray)
                    .frame(width: 8, height: 8)
                Text(session.telemetry.connectionState)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.45, blue: 0.32))
                if session.telemetry.towerHandoffCount > 0 {
                    Text("• Handoffs: \(session.telemetry.towerHandoffCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(red: 0.93, green: 0.98, blue: 0.95), in: Capsule())
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26))
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 6)
    }

    // MARK: - 4. Live Spoken Bubble (While Dr. Mohit is talking)

    @ViewBuilder
    private var liveSpokenBubbleCard: some View {
        if !speech.liveTranscript.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.caption.weight(.bold))
                    Text("Hearing You (Say 'Over' to Finish)")
                        .font(.caption2.weight(.heavy))
                        .tracking(0.5)
                    Spacer()
                    Button("Send Now") {
                        speech.forceSubmitCurrentTranscript()
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.06, green: 0.73, blue: 0.51))
                }
                .foregroundStyle(Color(red: 0.06, green: 0.73, blue: 0.51))

                Text(speech.liveTranscript)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(Color(red: 0.93, green: 0.98, blue: 0.95), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 0.06, green: 0.73, blue: 0.51).opacity(0.35), lineWidth: 1.5)
            )
        }
    }

    // MARK: - 5. Active Turn Response Card (Model Answer)

    @ViewBuilder
    private var latestTurnCard: some View {
        if !session.liveModelTranscript.isEmpty || !session.liveUserTranscript.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !session.liveUserTranscript.isEmpty {
                    Text(session.liveUserTranscript)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.31, green: 0.27, blue: 0.90), Color(red: 0.05, green: 0.65, blue: 0.91)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                }
                if !session.liveModelTranscript.isEmpty {
                    Text(session.liveModelTranscript)
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.95, green: 0.97, blue: 1.00), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        }
    }

    // MARK: - 6. Clean Optional Input Bar

    @ViewBuilder
    private var bottomComposerBar: some View {
        HStack(spacing: 10) {
            TextField("Type a question or Antigravity roadmap note...", text: $commandInput)
                .textFieldStyle(.plain)
                .padding(12)
                .foregroundStyle(Color(red: 0.07, green: 0.09, blue: 0.15))

            Button {
                let cmd = commandInput
                commandInput = ""
                Task {
                    await session.sendVoiceOrTextCommand(cmd)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(red: 0.31, green: 0.27, blue: 0.90))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}
