import AppKit
import SwiftUI

/// In-memory cache of favicons keyed by host. Populated as tabs load their
/// icons (delivered by CEF), and read by both the tab list and the Link
/// Library so saved links from sites you've visited show their real icon.
@MainActor
final class FaviconStore: ObservableObject {
    static let shared = FaviconStore()

    @Published private(set) var icons: [String: NSImage] = [:]

    func set(_ image: NSImage, forHost host: String) {
        guard !host.isEmpty else { return }
        icons[host] = image
    }

    func icon(for url: URL?) -> NSImage? {
        guard let host = url?.host else { return nil }
        return icons[host]
    }

    func icon(forURLString string: String) -> NSImage? {
        icon(for: URL(string: string))
    }
}
