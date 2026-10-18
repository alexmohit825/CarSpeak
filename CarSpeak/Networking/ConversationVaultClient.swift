import Foundation

/// Synchronizes archived conversations and all 56 Antigravity (AG) project dossiers
/// between Cloudflare Edge KV (`https://carspeak-api.mohalex.workers.dev`) and local iPhone storage.
final class ConversationVaultClient: ObservableObject {
    static let shared = ConversationVaultClient()

    let baseURL = "https://carspeak-api.mohalex.workers.dev"

    @Published var conversations: [ConversationThread] = []
    @Published var activeConversation: ConversationThread?
    @Published var agProjects: [AGProjectDossier] = []
    @Published var isSyncing: Bool = false

    private let localConversationsKey = "carspeak_archived_conversations_v2_clean"
    private let localActiveIdKey = "carspeak_active_conversation_id_v2_clean"

    init() {
        loadBundledAGPortfolioSeed()
        loadCachedConversations()
        Task {
            await syncAllFromCloud()
        }
    }

    /// Loads the 56 Antigravity projects bundled in `AGPortfolioSeed.json` immediately on launch
    /// so CarSpeak has 100% zero-latency offline and online knowledge of Dr. Mohit's portfolio.
    private func loadBundledAGPortfolioSeed() {
        if let url = Bundle.main.url(forResource: "AGPortfolioSeed", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([AGProjectDossier].self, from: data) {
            self.agProjects = decoded
        }
    }

    private func loadCachedConversations() {
        if let data = UserDefaults.standard.data(forKey: localConversationsKey),
           let decoded = try? JSONDecoder().decode([ConversationThread].self, from: data),
           !decoded.isEmpty {
            self.conversations = decoded
            let activeId = UserDefaults.standard.string(forKey: localActiveIdKey)
            self.activeConversation = decoded.first(where: { $0.id == activeId }) ?? decoded.first
        }
    }

    private func cacheConversationsLocally() {
        if let encoded = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(encoded, forKey: localConversationsKey)
        }
        if let activeId = activeConversation?.id {
            UserDefaults.standard.set(activeId, forKey: localActiveIdKey)
        }
    }

    @MainActor
    func syncAllFromCloud() async {
        isSyncing = true
        defer { isSyncing = false }

        // 1. Sync Archived Conversations
        if let convURL = URL(string: "\(baseURL)/api/conversations") {
            do {
                let (data, _) = try await URLSession.shared.data(from: convURL)
                struct ConvResponse: Decodable {
                    let activeConversationId: String?
                    let conversations: [ConversationThread]
                }
                let decoded = try JSONDecoder().decode(ConvResponse.self, from: data)
                if !decoded.conversations.isEmpty {
                    self.conversations = decoded.conversations
                    if let activeId = decoded.activeConversationId,
                       let found = decoded.conversations.first(where: { $0.id == activeId }) {
                        self.activeConversation = found
                    } else if self.activeConversation == nil {
                        self.activeConversation = decoded.conversations.first
                    }
                    cacheConversationsLocally()
                }
            } catch {
                print("[ConversationVaultClient] Offline/cached mode for conversations: \(error.localizedDescription)")
            }
        }

        // 2. Sync Antigravity Projects Portfolio
        if let projURL = URL(string: "\(baseURL)/api/projects") {
            do {
                let (data, _) = try await URLSession.shared.data(from: projURL)
                struct ProjResponse: Decodable {
                    let projects: [AGProjectDossier]
                }
                let decoded = try JSONDecoder().decode(ProjResponse.self, from: data)
                if !decoded.projects.isEmpty {
                    self.agProjects = decoded.projects
                }
            } catch {
                print("[ConversationVaultClient] Using bundled 56 AG projects seed.")
            }
        }
    }

    @MainActor
    func switchConversation(queryOrId: String) async -> ConversationThread? {
        guard let url = URL(string: "\(baseURL)/api/conversations") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = ["action": "switch", "targetQuery": queryOrId]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            struct SwitchResp: Decodable {
                let status: String
                let switchedConversation: ConversationThread?
            }
            let decoded = try JSONDecoder().decode(SwitchResp.self, from: data)
            if let switched = decoded.switchedConversation {
                self.activeConversation = switched
                if let idx = self.conversations.firstIndex(where: { $0.id == switched.id }) {
                    self.conversations[idx] = switched
                }
                cacheConversationsLocally()
                AcousticEarcons.shared.play(.threadSwitched)
                return switched
            }
        } catch {
            // Local fallback match
            let q = queryOrId.lowercased()
            if let localMatch = conversations.first(where: {
                $0.id.lowercased() == q ||
                $0.title.lowercased().contains(q) ||
                ($0.projectName ?? "").lowercased().contains(q)
            }) {
                self.activeConversation = localMatch
                cacheConversationsLocally()
                AcousticEarcons.shared.play(.threadSwitched)
                return localMatch
            }
        }
        return nil
    }

    @MainActor
    func startNewConversation(title: String, projectName: String = "") async -> ConversationThread? {
        guard let url = URL(string: "\(baseURL)/api/conversations") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "action": "create",
            "title": title,
            "projectName": projectName
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            struct CreateResp: Decodable {
                let newConversation: ConversationThread?
            }
            let decoded = try JSONDecoder().decode(CreateResp.self, from: data)
            if let created = decoded.newConversation {
                self.conversations.insert(created, at: 0)
                self.activeConversation = created
                cacheConversationsLocally()
                AcousticEarcons.shared.play(.threadSwitched)
                return created
            }
        } catch {
            print("[ConversationVaultClient] Create thread error: \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    func appendTurn(userText: String?, modelText: String?, persona: PersonaMode) async {
        guard let activeId = activeConversation?.id,
              let url = URL(string: "\(baseURL)/api/conversations") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: String] = [
            "action": "append_turn",
            "conversationId": activeId,
            "persona": persona.rawValue
        ]
        if let u = userText { payload["userText"] = u }
        if let m = modelText { payload["modelText"] = m }
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            struct AppendResp: Decodable {
                let conversation: ConversationThread?
            }
            let decoded = try JSONDecoder().decode(AppendResp.self, from: data)
            if let updated = decoded.conversation {
                self.activeConversation = updated
                if let idx = self.conversations.firstIndex(where: { $0.id == updated.id }) {
                    self.conversations[idx] = updated
                }
                cacheConversationsLocally()
            }
        } catch {
            print("[ConversationVaultClient] Append turn warning: \(error.localizedDescription)")
        }
    }
}
