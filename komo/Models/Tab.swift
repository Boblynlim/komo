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
    @Published var favicon: NSImage?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isPinned: Bool = false
    @Published var isFavorite: Bool = false

    init(id: UUID = UUID()) {
        self.id = id
        // CEF's accelerated surface composites into a CALayer — the host must
        // be layer-backed or the rendered page won't be visible.
        hostView.wantsLayer = true
    }

    /// Create the Chromium browser in `hostView`. Safe to call repeatedly.
    func ensureBrowser() {
        guard browser == nil else { return }
        let initial = (pendingURL ?? url)?.absoluteString ?? "https://example.com"
        let viewPtr = Unmanaged.passUnretained(hostView).toOpaque()
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let callbacks = KomoBrowserCallbacks(
            onTitleChange: { ud, v in
                // Copy the C string to a Swift String now — it's freed when this returns.
                let s = v.map { String(cString: $0) } ?? ""
                Tab.onMain(ud) { $0.title = s }
            },
            onURLChange: { ud, v in
                let s = v.map { String(cString: $0) }
                Tab.onMain(ud) { $0.url = s.flatMap { URL(string: $0) } }
            },
            onLoadingChange: { ud, v in Tab.onMain(ud) { $0.isLoading = v } },
            onCanGoBackChange: { ud, v in Tab.onMain(ud) { $0.canGoBack = v } },
            onCanGoForwardChange: { ud, v in Tab.onMain(ud) { $0.canGoForward = v } },
            onFaviconChange: { ud, data, len in
                // Copy the PNG bytes now — the buffer is freed when this returns.
                guard let data, len > 0 else { return }
                let bytes = Data(bytes: data, count: Int(len))
                Tab.onMain(ud) { tab in
                    guard let image = NSImage(data: bytes) else { return }
                    tab.favicon = image
                    if let host = tab.url?.host {
                        FaviconStore.shared.set(image, forHost: host)
                    }
                }
            }
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
    func setBrowserFocus(_ focused: Bool) { if let b = browser { komo_cef_set_focus(b, focused) } }

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
