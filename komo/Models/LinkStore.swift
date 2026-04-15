import Foundation
import Combine

class LinkStore: ObservableObject {
    @Published var links: [SavedLink] = []
    @Published var selectedTag: String? = nil
    @Published var searchQuery: String = ""
    @Published var filter: LinkFilter = .inbox

    enum LinkFilter: Equatable {
        case inbox
        case archive
        case tag(String)
        case search
    }

    private let saveURL: URL

    var allTags: [String] {
        let tagSet = Set(links.flatMap { $0.tags })
        return tagSet.sorted()
    }

    var filteredLinks: [SavedLink] {
        var result: [SavedLink]

        switch filter {
        case .inbox:
            result = links.filter { !$0.isArchived }
        case .archive:
            result = links.filter { $0.isArchived }
        case .tag(let tag):
            result = links.filter { $0.tags.contains(tag) }
        case .search:
            result = links
        }

        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                $0.url.lowercased().contains(query) ||
                $0.tags.contains { $0.lowercased().contains(query) } ||
                $0.notes.lowercased().contains(query)
            }
        }

        return result.sorted { $0.savedAt > $1.savedAt }
    }

    /// Group filtered links by date
    var groupedLinks: [(String, [SavedLink])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredLinks) { link -> String in
            if calendar.isDateInToday(link.savedAt) {
                return "Today"
            } else if calendar.isDateInYesterday(link.savedAt) {
                return "Yesterday"
            } else if let daysAgo = calendar.dateComponents([.day], from: link.savedAt, to: .now).day, daysAgo < 7 {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE"
                return formatter.string(from: link.savedAt)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy"
                return formatter.string(from: link.savedAt)
            }
        }
        return grouped.sorted { $0.value.first!.savedAt > $1.value.first!.savedAt }
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let komoDir = appSupport.appendingPathComponent("komo", isDirectory: true)
        try? FileManager.default.createDirectory(at: komoDir, withIntermediateDirectories: true)
        self.saveURL = komoDir.appendingPathComponent("saved-links.json")
        load()
    }

    func save(url: String, title: String, tags: [String] = [], notes: String = "") {
        // Don't save duplicates
        guard !links.contains(where: { $0.url == url }) else { return }
        let link = SavedLink(url: url, title: title, tags: tags, notes: notes)
        links.insert(link, at: 0)
        persist()
    }

    func delete(_ link: SavedLink) {
        links.removeAll { $0.id == link.id }
        persist()
    }

    func archive(_ link: SavedLink) {
        if let index = links.firstIndex(where: { $0.id == link.id }) {
            links[index].isArchived = true
            persist()
        }
    }

    func unarchive(_ link: SavedLink) {
        if let index = links.firstIndex(where: { $0.id == link.id }) {
            links[index].isArchived = false
            persist()
        }
    }

    func updateTags(_ link: SavedLink, tags: [String]) {
        if let index = links.firstIndex(where: { $0.id == link.id }) {
            links[index].tags = tags
            persist()
        }
    }

    func addTag(_ tag: String, to link: SavedLink) {
        if let index = links.firstIndex(where: { $0.id == link.id }) {
            if !links[index].tags.contains(tag) {
                links[index].tags.append(tag)
                persist()
            }
        }
    }

    func deleteTag(_ tag: String) {
        for i in links.indices {
            links[i].tags.removeAll { $0 == tag }
        }
        if case .tag(let t) = filter, t == tag {
            filter = .inbox
        }
        persist()
    }

    func renameTag(_ oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        for i in links.indices {
            if let tagIndex = links[i].tags.firstIndex(of: oldName) {
                links[i].tags[tagIndex] = trimmed
            }
        }
        if case .tag(let t) = filter, t == oldName {
            filter = .tag(trimmed)
        }
        persist()
    }

    /// Auto-suggest tags based on URL domain
    func suggestTags(for url: String) -> [String] {
        guard let parsed = URL(string: url), let host = parsed.host else { return [] }

        var suggestions: [String] = []

        // Domain-based suggestions
        let domain = host.replacingOccurrences(of: "www.", with: "")
        let known: [String: [String]] = [
            "github.com": ["dev", "code"],
            "dribbble.com": ["design"],
            "figma.com": ["design"],
            "medium.com": ["reading"],
            "youtube.com": ["video"],
            "twitter.com": ["social"],
            "x.com": ["social"],
            "reddit.com": ["social"],
            "stackoverflow.com": ["dev"],
            "arxiv.org": ["research"],
            "news.ycombinator.com": ["dev", "news"],
        ]

        if let tags = known[domain] {
            suggestions.append(contentsOf: tags)
        }

        // Suggest existing tags that were used with this domain before
        let domainLinks = links.filter { link in
            URL(string: link.url)?.host?.replacingOccurrences(of: "www.", with: "") == domain
        }
        let domainTags = Set(domainLinks.flatMap { $0.tags })
        suggestions.append(contentsOf: domainTags)

        return Array(Set(suggestions)).sorted()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let data = try JSONEncoder().encode(links)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save links: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        if let decoded = try? JSONDecoder().decode([SavedLink].self, from: data) {
            links = decoded
        }
    }
}
