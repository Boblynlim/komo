import Foundation
import WebKit

class DownloadItem: Identifiable, ObservableObject {
    let id = UUID()
    let fileName: String
    let url: URL
    let startedAt: Date
    @Published var progress: Double = 0
    @Published var isComplete: Bool = false
    @Published var localURL: URL?
    @Published var error: String?

    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(startedAt))
        if seconds < 60 { return "\(seconds) seconds ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s") ago" }
        let hours = minutes / 60
        return "\(hours) hour\(hours == 1 ? "" : "s") ago"
    }

    init(fileName: String, url: URL) {
        self.fileName = fileName
        self.url = url
        self.startedAt = .now
    }
}

class DownloadManager: NSObject, ObservableObject {
    @Published var downloads: [DownloadItem] = []
    @Published var latestDownload: DownloadItem? = nil
    @Published var showLatestPopup: Bool = false

    private var activeDownloads: [WKDownload: DownloadItem] = [:]
    private var popupTimer: Timer?

    var recentDownloads: [DownloadItem] {
        downloads.sorted { $0.startedAt > $1.startedAt }
    }

    func startDownload(_ download: WKDownload, suggestedFilename: String, url: URL) -> URL {
        let item = DownloadItem(fileName: suggestedFilename, url: url)
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destination = downloadsDir.appendingPathComponent(suggestedFilename)

        item.localURL = destination
        activeDownloads[download] = item

        DispatchQueue.main.async {
            self.downloads.insert(item, at: 0)
            self.latestDownload = item
            self.showLatestPopup = true

            self.popupTimer?.invalidate()
            self.popupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
                DispatchQueue.main.async {
                    self.showLatestPopup = false
                }
            }
        }

        return destination
    }

    func updateProgress(_ download: WKDownload, progress: Double) {
        guard let item = activeDownloads[download] else { return }
        DispatchQueue.main.async {
            item.progress = progress
        }
    }

    func completeDownload(_ download: WKDownload) {
        guard let item = activeDownloads[download] else { return }
        DispatchQueue.main.async {
            item.isComplete = true
            item.progress = 1.0
        }
        activeDownloads.removeValue(forKey: download)
    }

    func failDownload(_ download: WKDownload, error: Error) {
        guard let item = activeDownloads[download] else { return }
        DispatchQueue.main.async {
            item.error = error.localizedDescription
        }
        activeDownloads.removeValue(forKey: download)
    }

    func revealInFinder(_ item: DownloadItem) {
        if let url = item.localURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
