import AppKit
import KomoCEF

class Tab: Identifiable, ObservableObject {
    let id: UUID
    // The Chromium browser is parented into this view, created lazily once the
    // view is in a window (see WebViewContainer).
    let hostView = NSView()
    private var browser: UnsafeMutableRawPointer?
    private var pendingURL: URL?

    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isPinned: Bool = false
    @Published var isFavorite: Bool = false

    init(id: UUID = UUID()) {
        self.id = id
    }

    /// Create the Chromium browser in `hostView`. Safe to call repeatedly.
    func ensureBrowser() {
        guard browser == nil else { return }
        let initial = (pendingURL ?? url)?.absoluteString ?? "https://example.com"
        let viewPtr = Unmanaged.passUnretained(hostView).toOpaque()
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let callbacks = KomoBrowserCallbacks(
            onTitleChange: { ud, v in
                Tab.onMain(ud) { $0.title = v.map { String(cString: $0) } ?? "" }
            },
            onURLChange: { ud, v in
                Tab.onMain(ud) { $0.url = v.flatMap { URL(string: String(cString: $0)) } }
            },
            onLoadingChange: { ud, v in Tab.onMain(ud) { $0.isLoading = v } },
            onCanGoBackChange: { ud, v in Tab.onMain(ud) { $0.canGoBack = v } },
            onCanGoForwardChange: { ud, v in Tab.onMain(ud) { $0.canGoForward = v } }
        )
        browser = komo_cef_create_browser(viewPtr, initial, userData, callbacks)
        pendingURL = nil
    }

    // Resolve the Tab from the C callback's userData and apply `body` on the main thread.
    private static func onMain(_ ud: UnsafeMutableRawPointer?, _ body: @escaping (Tab) -> Void) {
        guard let ud = ud else { return }
        let tab = Unmanaged<Tab>.fromOpaque(ud).takeUnretainedValue()
        DispatchQueue.main.async { body(tab) }
    }

    func load(_ url: URL) {
        self.url = url
        if let b = browser {
            komo_cef_load_url(b, url.absoluteString)
        } else {
            pendingURL = url
        }
    }

    func reload() { if let b = browser { komo_cef_reload(b) } }
    func goBack() { if let b = browser { komo_cef_go_back(b) } }
    func goForward() { if let b = browser { komo_cef_go_forward(b) } }
    func stopLoading() { if let b = browser { komo_cef_stop_load(b) } }

    func closeBrowser() {
        if let b = browser { komo_cef_close_browser(b) }
        browser = nil
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
