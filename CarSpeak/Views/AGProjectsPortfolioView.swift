import SwiftUI

struct AGProjectsPortfolioView: View {
    @ObservedObject var vault = ConversationVaultClient.shared
    @ObservedObject var session = GeminiLiveSessionManager.shared
    @State private var searchText: String = ""

    var filteredProjects: [AGProjectDossier] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vault.agProjects }
        return vault.agProjects.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            $0.summary.lowercased().contains(q) ||
            $0.recentFocus.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredProjects) { project in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(project.displayName)
                                    .font(.headline)
                                Spacer()
                                Text(project.lastModified)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text(project.category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.cyan)

                            Text(project.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Focus: \(project.recentFocus)")
                                .font(.caption2)
                                .foregroundStyle(.primary.opacity(0.85))

                            if let notes = project.roadmapNotes, !notes.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(notes.prefix(3)) { note in
                                        Label(note.note, systemImage: "checkmark.circle.fill")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.mint)
                                    }
                                }
                                .padding(.top, 2)
                            }

                            Button {
                                Task {
                                    await session.sendVoiceOrTextCommand(
                                        "Pull up our Antigravity project \(project.displayName) and let's pick up right where we left off."
                                    )
                                }
                            } label: {
                                Label("Resume in CarSpeak Voice Session", systemImage: "waveform.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.cyan.opacity(0.16), in: Capsule())
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Antigravity Developed Portfolio (\(filteredProjects.count) Projects)")
                }
            }
            .searchable(text: $searchText, prompt: "Search 56 Antigravity apps (Radix, DuralGuard, MDEsq...)")
            .navigationTitle("AG Projects (\(vault.agProjects.count))")
        }
    }
}
