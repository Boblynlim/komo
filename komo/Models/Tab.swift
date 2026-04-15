import Foundation
import WebKit

class Tab: Identifiable, ObservableObject {
    let id: UUID
    let webView: WKWebView

    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isPinned: Bool = false
    @Published var isFavorite: Bool = false

    init(id: UUID = UUID(), configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        self.id = id
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        self.url = url
        webView.load(URLRequest(url: url))
    }

    func reload() {
        webView.reload()
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }
}

// For session persistence
struct TabSession: Codable {
    let id: String
    let url: String?
    let title: String
    let isPinned: Bool
    let isFavorite: Bool
    let folderID: String?
}
