import Foundation

struct PulseRecommendation: Identifiable, Codable {
    let id: UUID
    var title: String
    var url: String
    var description: String
    var reason: String // why this was recommended
    var tags: [String]
    var domain: String
    var feedback: Feedback?

    enum Feedback: String, Codable {
        case liked
        case dismissed
    }

    init(title: String, url: String, description: String, reason: String, tags: [String], domain: String) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.description = description
        self.reason = reason
        self.tags = tags
        self.domain = domain
    }
}

class PulseEngine: ObservableObject {
    @Published var recommendations: [PulseRecommendation] = []
    @Published var isLoading: Bool = false
    @Published var lastRefreshed: Date? = nil
    @Published var error: String? = nil

    private var apiKey: String {
        // Check environment, then stored preference
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            return key
        }
        return UserDefaults.standard.string(forKey: "anthropic_api_key") ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "anthropic_api_key")
    }

    private let persistURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let komoDir = appSupport.appendingPathComponent("komo", isDirectory: true)
        try? FileManager.default.createDirectory(at: komoDir, withIntermediateDirectories: true)
        return komoDir.appendingPathComponent("pulse-recommendations.json")
    }()

    init() {
        loadCached()
    }

    func refresh(links: [SavedLink]) async {
        guard hasAPIKey else {
            await MainActor.run { error = "No API key set" }
            return
        }

        await MainActor.run {
            isLoading = true
            error = nil
        }

        let profile = TasteGraphBuilder.build(from: links)
        let profilePrompt = TasteGraphBuilder.formatForPrompt(profile, recentLinks: links)

        // Build liked/dismissed history for better recs
        let likedTitles = recommendations.filter { $0.feedback == .liked }.map { $0.title }
        let dismissedTitles = recommendations.filter { $0.feedback == .dismissed }.map { $0.title }

        let systemPrompt = """
        You are Pulse, a personal internet scout. Your job is to recommend interesting websites, \
        articles, tools, and rabbit holes based on the user's taste profile.

        Rules:
        - Recommend 8 items
        - Each item must be a real, existing website or article
        - Focus on discovering things they HAVEN'T seen, not popular mainstream sites
        - Match their interests but also surprise them with adjacent topics
        - No paywalled content unless it has a free tier
        - Respond ONLY with valid JSON, no markdown

        Respond with this exact JSON format:
        [
            {
                "title": "Site or Article Title",
                "url": "https://example.com",
                "description": "One sentence about what this is",
                "reason": "Why this matches their taste",
                "tags": ["tag1", "tag2"],
                "domain": "example.com"
            }
        ]
        """

        var userPrompt = profilePrompt

        if !likedTitles.isEmpty {
            userPrompt += "\n\n## Previously liked recommendations\n"
            for title in likedTitles.suffix(5) {
                userPrompt += "- \(title)\n"
            }
        }
        if !dismissedTitles.isEmpty {
            userPrompt += "\n\n## Previously dismissed (don't recommend similar)\n"
            for title in dismissedTitles.suffix(5) {
                userPrompt += "- \(title)\n"
            }
        }

        userPrompt += "\n\nBased on this profile, recommend 8 interesting sites, articles, or tools I'd love. Return JSON only."

        do {
            let recs = try await callClaude(system: systemPrompt, user: userPrompt)
            await MainActor.run {
                self.recommendations = recs
                self.lastRefreshed = .now
                self.isLoading = false
                self.persistCache()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func like(_ rec: PulseRecommendation) {
        if let index = recommendations.firstIndex(where: { $0.id == rec.id }) {
            recommendations[index].feedback = .liked
            persistCache()
        }
    }

    func dismiss(_ rec: PulseRecommendation) {
        if let index = recommendations.firstIndex(where: { $0.id == rec.id }) {
            recommendations[index].feedback = .dismissed
            persistCache()
        }
    }

    var activeRecommendations: [PulseRecommendation] {
        recommendations.filter { $0.feedback != .dismissed }
    }

    // MARK: - Claude API

    private func callClaude(system: String, user: String) async throws -> [PulseRecommendation] {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PulseError.apiError(errorText)
        }

        // Parse Claude response
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw PulseError.parseError("No text in response")
        }

        // Extract JSON from response (Claude might wrap it)
        let jsonText = extractJSON(from: text)
        let recData = jsonText.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([PulseRecommendation].self, from: recData)
        return decoded
    }

    private func extractJSON(from text: String) -> String {
        // Try to find JSON array in the response
        if let start = text.firstIndex(of: "["),
           let end = text.lastIndex(of: "]") {
            return String(text[start...end])
        }
        return text
    }

    // MARK: - Persistence

    private func persistCache() {
        do {
            let data = try JSONEncoder().encode(recommendations)
            try data.write(to: persistURL, options: .atomic)
        } catch {
            print("Failed to cache pulse: \(error)")
        }
    }

    private func loadCached() {
        guard let data = try? Data(contentsOf: persistURL),
              let decoded = try? JSONDecoder().decode([PulseRecommendation].self, from: data) else { return }
        recommendations = decoded
    }
}

enum PulseError: LocalizedError {
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "API error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
