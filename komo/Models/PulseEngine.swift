import Foundation

struct PulseRecommendation: Identifiable, Codable {
    let id: UUID
    var title: String
    var url: String
    var description: String
    var reason: String
    var tags: [String]
    var domain: String
    var category: String
    var feedback: Feedback?

    enum Feedback: String, Codable {
        case liked
        case dismissed
    }

    init(title: String, url: String, description: String, reason: String, tags: [String], domain: String, category: String) {
        self.id = UUID()
        self.title = title
        self.url = url
        self.description = description
        self.reason = reason
        self.tags = tags
        self.domain = domain
        self.category = category
    }
}

class PulseEngine: ObservableObject {
    @Published var recommendations: [PulseRecommendation] = []
    @Published var isLoading: Bool = false
    @Published var lastRefreshed: Date? = nil
    @Published var error: String? = nil

    private var apiKey: String {
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
        if recommendations.isEmpty {
            loadPlaceholders()
        }
    }

    /// Categories in display order
    var categories: [String] {
        var seen: [String] = []
        for rec in activeRecommendations {
            if !seen.contains(rec.category) {
                seen.append(rec.category)
            }
        }
        return seen
    }

    func recommendations(for category: String) -> [PulseRecommendation] {
        activeRecommendations.filter { $0.category == category }
    }

    private func loadPlaceholders() {
        recommendations = [
            // — Interactive & Visual
            PulseRecommendation(
                title: "Bartosz Ciechanowski",
                url: "https://ciechanow.ski",
                description: "Deep, beautifully animated explanations of how things work — GPS, cameras, mechanical watches. Each post takes months to craft and it shows.",
                reason: "The gold standard for interactive technical writing",
                tags: ["engineering", "interactive", "visualization"],
                domain: "ciechanow.ski",
                category: "Interactive & Visual"
            ),
            PulseRecommendation(
                title: "Neal.fun",
                url: "https://neal.fun",
                description: "Playful interactive experiments — the size of space, spend Bill Gates' money, the deep sea. Each one is a tiny, perfect rabbit hole.",
                reason: "Delightful one-person web toys",
                tags: ["interactive", "fun", "visualization"],
                domain: "neal.fun",
                category: "Interactive & Visual"
            ),

            // — Indie Discovery
            PulseRecommendation(
                title: "Marginalia Search",
                url: "https://search.marginalia.nu",
                description: "A search engine that intentionally surfaces small, independent websites instead of SEO-optimized content farms. The anti-Google.",
                reason: "Rediscover the weird, personal web",
                tags: ["search", "indie-web", "discovery"],
                domain: "search.marginalia.nu",
                category: "Indie Discovery"
            ),
            PulseRecommendation(
                title: "Hundred Rabbits",
                url: "https://100r.co",
                description: "Two artists on a sailboat building open-source creative tools that run on minimal hardware. Software as a lifestyle philosophy.",
                reason: "Indie software meets unconventional living",
                tags: ["indie", "creative-tools", "open-source"],
                domain: "100r.co",
                category: "Indie Discovery"
            ),
            PulseRecommendation(
                title: "XXIIVV — Devine Lu Linvega",
                url: "https://wiki.xxiivv.com",
                description: "A personal wiki spanning programming languages, music, sailing logs, and conlangs. Beautifully handcrafted.",
                reason: "A digital garden that feels like discovering someone's whole world",
                tags: ["wiki", "personal", "creative-coding"],
                domain: "wiki.xxiivv.com",
                category: "Indie Discovery"
            ),

            // — Unconventional Tech
            PulseRecommendation(
                title: "Low Tech Magazine — Solar Powered",
                url: "https://solar.lowtechmagazine.com",
                description: "A solar-powered website about sustainable technology and forgotten innovations. When the sun doesn't shine, the site goes down. On purpose.",
                reason: "Technology criticism that practices what it preaches",
                tags: ["sustainability", "technology", "design"],
                domain: "solar.lowtechmagazine.com",
                category: "Unconventional Tech"
            ),
            PulseRecommendation(
                title: "The Pudding",
                url: "https://pudding.cool",
                description: "Visual essays on culture, language, music, and trends — each one is a small interactive masterpiece backed by real data.",
                reason: "Data journalism with craft and taste",
                tags: ["data-viz", "culture", "essays"],
                domain: "pudding.cool",
                category: "Unconventional Tech"
            ),

            // — Deep Dives
            PulseRecommendation(
                title: "Algorithms by Jeff Erickson",
                url: "https://jeffe.cs.illinois.edu/teaching/algorithms/",
                description: "A free, beautifully written algorithms textbook used at top CS programs. Clear prose, no hand-waving, excellent exercises.",
                reason: "The algorithms textbook you wish you'd had",
                tags: ["algorithms", "cs", "textbook"],
                domain: "jeffe.cs.illinois.edu",
                category: "Deep Dives"
            ),
            PulseRecommendation(
                title: "href.cool",
                url: "https://href.cool",
                description: "A curated link directory of the weird and wonderful web — organized by vibes, not SEO. Someone's personal collection of internet treasures.",
                reason: "A human-curated map of the interesting internet",
                tags: ["links", "curation", "directory"],
                domain: "href.cool",
                category: "Deep Dives"
            ),
        ]
        lastRefreshed = .now
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

        let likedTitles = recommendations.filter { $0.feedback == .liked }.map { $0.title }
        let dismissedTitles = recommendations.filter { $0.feedback == .dismissed }.map { $0.title }

        let systemPrompt = """
        You are Scout, a personal internet scout. Your job is to recommend interesting websites, \
        articles, tools, and rabbit holes based on the user's taste profile.

        Discovery philosophy:
        - Do NOT rely on SEO prominence. A site's Google ranking is irrelevant to whether it's good.
        - Discover the way webrings, blogrolls, and human-curated directories discover — by \
          following links from interesting places, not by searching keywords.
        - The best recommendation is something they'd never find through a search engine but \
          would love once they see it.
        - A wide range is good: personal pages, tools, academic resources, niche communities, \
          interactive experiments, small company projects, one-person blogs, institutional \
          archives, fan sites — anything that's genuinely good.
        - Draw from the full web: Neocities pages and MIT research papers are both fair game. \
          The filter is quality and relevance, not size or polish.
        - Think like someone browsing through a webring, an Are.na channel, a blogroll, or a \
          human-curated link directory — not like someone googling.

        Rules:
        - Recommend 8-10 items grouped into 3-5 categories
        - Each item must be a real, existing website or article
        - Don't default to the sites that rank highest on Google — dig deeper
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
                "domain": "example.com",
                "category": "Category Name"
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

        userPrompt += "\n\nBased on this profile, recommend 8-10 interesting sites grouped by category. Return JSON only."

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
            recommendations[index].feedback = (recommendations[index].feedback == .liked) ? nil : .liked
            persistCache()
        }
    }

    func dislike(_ rec: PulseRecommendation) {
        if let index = recommendations.firstIndex(where: { $0.id == rec.id }) {
            recommendations[index].feedback = (recommendations[index].feedback == .dismissed) ? nil : .dismissed
            persistCache()
        }
    }

    var activeRecommendations: [PulseRecommendation] {
        recommendations
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
            "max_tokens": 2048,
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

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw PulseError.parseError("No text in response")
        }

        let jsonText = extractJSON(from: text)
        let recData = jsonText.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([PulseRecommendation].self, from: recData)
        return decoded
    }

    private func extractJSON(from text: String) -> String {
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
