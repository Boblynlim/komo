import Foundation

struct TasteProfile: Codable {
    var interests: [Interest]
    var topDomains: [DomainFrequency]
    var lastUpdated: Date

    struct Interest: Codable, Identifiable {
        let id = UUID()
        var name: String
        var weight: Double // 0.0 to 1.0, how much they care about this
        var tags: [String] // related tags from saved links

        enum CodingKeys: String, CodingKey {
            case name, weight, tags
        }
    }

    struct DomainFrequency: Codable {
        var domain: String
        var count: Int
    }
}

class TasteGraphBuilder {

    /// Build a taste profile from saved links
    static func build(from links: [SavedLink]) -> TasteProfile {
        guard !links.isEmpty else {
            return TasteProfile(interests: [], topDomains: [], lastUpdated: .now)
        }

        // Count tags
        var tagCounts: [String: Int] = [:]
        for link in links {
            for tag in link.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        // Count domains
        var domainCounts: [String: Int] = [:]
        for link in links {
            if let url = URL(string: link.url), let host = url.host {
                let domain = host.replacingOccurrences(of: "www.", with: "")
                domainCounts[domain, default: 0] += 1
            }
        }

        // Cluster tags into interests
        let maxCount = Double(tagCounts.values.max() ?? 1)
        let interests = tagCounts
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { tag, count in
                TasteProfile.Interest(
                    name: tag,
                    weight: Double(count) / maxCount,
                    tags: [tag]
                )
            }

        let topDomains = domainCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { TasteProfile.DomainFrequency(domain: $0.key, count: $0.value) }

        return TasteProfile(
            interests: Array(interests),
            topDomains: Array(topDomains),
            lastUpdated: .now
        )
    }

    /// Format taste profile as a prompt for Claude
    static func formatForPrompt(_ profile: TasteProfile, recentLinks: [SavedLink]) -> String {
        var prompt = "Here is a user's interest profile based on their saved links:\n\n"

        prompt += "## Interests (ranked by importance)\n"
        for interest in profile.interests.sorted(by: { $0.weight > $1.weight }) {
            let bar = String(repeating: "█", count: Int(interest.weight * 10))
            prompt += "- \(interest.name) \(bar) (\(Int(interest.weight * 100))%)\n"
        }

        prompt += "\n## Top domains they visit\n"
        for domain in profile.topDomains {
            prompt += "- \(domain.domain) (\(domain.count) saves)\n"
        }

        prompt += "\n## Recent saves (last 10)\n"
        for link in recentLinks.prefix(10) {
            let tags = link.tags.map { "#\($0)" }.joined(separator: " ")
            prompt += "- \(link.title) (\(link.url)) \(tags)\n"
        }

        return prompt
    }
}
