import Foundation

struct SavedLink: Identifiable, Codable, Equatable {
    let id: UUID
    var url: String
    var title: String
    var tags: [String]
    var notes: String
    var savedAt: Date
    var isArchived: Bool

    init(url: String, title: String, tags: [String] = [], notes: String = "", savedAt: Date = .now, isArchived: Bool = false) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.tags = tags
        self.notes = notes
        self.savedAt = savedAt
        self.isArchived = isArchived
    }
}
