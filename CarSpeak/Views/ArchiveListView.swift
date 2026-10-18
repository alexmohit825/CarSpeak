import SwiftUI

struct ArchiveListView: View {
    @ObservedObject var vault = ConversationVaultClient.shared
    @ObservedObject var session = GeminiLiveSessionManager.shared
    @State private var searchText: String = ""
    @State private var showingNewThreadAlert = false
    @State private var newThreadTitle = ""
    @State private var newThreadProject = ""

    var filteredThreads: [ConversationThread] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vault.conversations }
        return vault.conversations.filter {
            $0.title.lowercased().contains(q) ||
            ($0.projectName ?? "").lowercased().contains(q) ||
            $0.summary.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredThreads) { thread in
                        Button {
                            Task {
                                _ = await vault.switchConversation(queryOrId: thread.id)
                                await session.sendVoiceOrTextCommand("Switch to our conversation \(thread.title) and remind me where we left off.")
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(thread.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if vault.activeConversation?.id == thread.id {
                                        Text("ACTIVE")
                                            .font(.caption2.weight(.heavy))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.cyan.opacity(0.2), in: Capsule())
                                            .foregroundStyle(.cyan)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Label(thread.projectName ?? "General", systemImage: "folder.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.cyan)
                                    Text("• \(thread.turns.count) turns")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(thread.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Voice-Switchable Conversation Archive (\(filteredThreads.count))")
                } footer: {
                    Text("Tip: While driving on CarPlay, simply say \"Switch to my conversation about [Project or Topic]\" to load that thread hands-free.")
                }
            }
            .searchable(text: $searchText, prompt: "Search archived conversations or AG projects")
            .navigationTitle("Archived Threads")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewThreadAlert = true
                    } label: {
                        Label("New Thread", systemImage: "plus.bubble.fill")
                    }
                }
            }
            .alert("Start New Conversation", isPresented: $showingNewThreadAlert) {
                TextField("Conversation Title", text: $newThreadTitle)
                TextField("Linked AG Project (e.g. Radix, DuralGuard)", text: $newThreadProject)
                Button("Create & Switch") {
                    let title = newThreadTitle.isEmpty ? "New Commute Session" : newThreadTitle
                    let proj = newThreadProject
                    newThreadTitle = ""
                    newThreadProject = ""
                    Task {
                        _ = await vault.startNewConversation(title: title, projectName: proj)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
