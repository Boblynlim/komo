import Foundation
import WebKit
import Combine

struct FolderSession: Codable {
    let id: String
    let name: String
    let tabIDs: [String]
}

class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedTabID: UUID?
    @Published var isSidebarVisible: Bool = true
    @Published var folders: [TabFolder] = []

    private var contentRuleList: WKContentRuleList?
    private var observers: [UUID: [AnyCancellable]] = [:]
    private var sessionSaveCancellable: AnyCancellable?

    private var sessionURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let komoDir = appSupport.appendingPathComponent("komo", isDirectory: true)
        try? FileManager.default.createDirectory(at: komoDir, withIntermediateDirectories: true)
        return komoDir.appendingPathComponent("session.json")
    }

    var selectedTab: Tab? {
        guard let id = selectedTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    var unfolderedTabs: [Tab] {
        let folderedIDs = Set(folders.flatMap { $0.tabIDs })
        return tabs.filter { !folderedIDs.contains($0.id) }
    }

    func tab(for id: UUID) -> Tab? {
        tabs.first { $0.id == id }
    }

    init() {
        loadContentBlocker()

        if !restoreSession() {
            createNewTab(url: URL(string: "https://apple.com")!)
        }

        // Auto-save session when tabs change
        sessionSaveCancellable = objectWillChange
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.saveSession()
            }
    }

    func createNewTab(url: URL? = nil, isPinned: Bool = false) {
        // No URL = just open command bar, don't create an empty tab
        if url == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .toggleCommandBar, object: nil)
            }
            return
        }

        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true

        if let ruleList = contentRuleList {
            config.userContentController.add(ruleList)
        }

        let tab = Tab(configuration: config)
        tab.isPinned = isPinned
        setupObservers(for: tab)

        tabs.append(tab)
        selectedTabID = tab.id
        tab.load(url!)
    }

    private func setupObservers(for tab: Tab) {
        let titleObserver = tab.webView.publisher(for: \.title)
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .assign(to: \.title, on: tab)

        let urlObserver = tab.webView.publisher(for: \.url)
            .receive(on: DispatchQueue.main)
            .assign(to: \.url, on: tab)

        let loadingObserver = tab.webView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .assign(to: \.isLoading, on: tab)

        let backObserver = tab.webView.publisher(for: \.canGoBack)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canGoBack, on: tab)

        let forwardObserver = tab.webView.publisher(for: \.canGoForward)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canGoForward, on: tab)

        observers[tab.id] = [titleObserver, urlObserver, loadingObserver, backObserver, forwardObserver]
    }

    func closeTab(_ tab: Tab) {
        observers.removeValue(forKey: tab.id)
        for folder in folders {
            folder.tabIDs.removeAll { $0 == tab.id }
        }
        tabs.removeAll { $0.id == tab.id }

        if selectedTabID == tab.id {
            selectedTabID = tabs.last?.id
        }

        if tabs.isEmpty {
            createNewTab()
        }

        saveSession()
    }

    func closeCurrentTab() {
        guard let tab = selectedTab else { return }
        closeTab(tab)
    }

    func selectTab(_ tab: Tab) {
        selectedTabID = tab.id
    }

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    // MARK: - Favorites

    func toggleFavorite(_ tab: Tab) {
        tab.isFavorite.toggle()
        objectWillChange.send()
        saveSession()
    }

    // MARK: - Folders

    func createFolder(name: String) {
        let folder = TabFolder(name: name)
        folders.append(folder)
        saveSession()
    }

    func deleteFolder(_ folder: TabFolder) {
        folders.removeAll { $0.id == folder.id }
        saveSession()
    }

    func renameFolder(_ folder: TabFolder, to name: String) {
        folder.name = name
        objectWillChange.send()
        saveSession()
    }

    func moveTab(_ tab: Tab, toFolder folder: TabFolder) {
        tab.isPinned = false
        for f in folders {
            f.tabIDs.removeAll { $0 == tab.id }
        }
        folder.tabIDs.append(tab.id)
        objectWillChange.send()
        saveSession()
    }

    func removeTabFromFolder(_ tab: Tab) {
        for folder in folders {
            folder.tabIDs.removeAll { $0 == tab.id }
        }
        objectWillChange.send()
        saveSession()
    }

    // MARK: - Session Persistence

    func saveSession() {
        let tabSessions = tabs.map { tab in
            let folderID = folders.first { $0.tabIDs.contains(tab.id) }?.id.uuidString
            return TabSession(
                id: tab.id.uuidString,
                url: tab.url?.absoluteString,
                title: tab.title,
                isPinned: tab.isPinned,
                isFavorite: tab.isFavorite,
                folderID: folderID
            )
        }

        let folderSessions = folders.map { folder in
            FolderSession(
                id: folder.id.uuidString,
                name: folder.name,
                tabIDs: folder.tabIDs.map { $0.uuidString }
            )
        }

        let session: [String: Any] = [
            "selectedTabID": selectedTabID?.uuidString ?? "",
        ]

        struct SessionData: Codable {
            let tabs: [TabSession]
            let folders: [FolderSession]
            let selectedTabID: String?
        }

        let data = SessionData(
            tabs: tabSessions,
            folders: folderSessions,
            selectedTabID: selectedTabID?.uuidString
        )

        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: sessionURL, options: .atomic)
        } catch {
            print("Failed to save session: \(error)")
        }
    }

    private func restoreSession() -> Bool {
        struct SessionData: Codable {
            let tabs: [TabSession]
            let folders: [FolderSession]
            let selectedTabID: String?
        }

        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(SessionData.self, from: data),
              !session.tabs.isEmpty else {
            return false
        }

        // Restore folders first
        for fs in session.folders {
            if let folderID = UUID(uuidString: fs.id) {
                let folder = TabFolder(name: fs.name)
                // We need to set the folder ID to match
                // TabFolder generates its own ID, so we store the mapping
                folders.append(folder)
            }
        }

        // Restore tabs
        for ts in session.tabs {
            guard let tabID = UUID(uuidString: ts.id) else { continue }

            let config = WKWebViewConfiguration()
            config.preferences.isElementFullscreenEnabled = true
            if let ruleList = contentRuleList {
                config.userContentController.add(ruleList)
            }

            let tab = Tab(id: tabID, configuration: config)
            tab.title = ts.title
            tab.isPinned = ts.isPinned
            tab.isFavorite = ts.isFavorite
            setupObservers(for: tab)
            tabs.append(tab)

            if let urlString = ts.url, let url = URL(string: urlString) {
                tab.load(url)
            }
        }

        // Restore folder tab assignments
        // Map old folder IDs to new folder objects by index
        for (index, fs) in session.folders.enumerated() where index < folders.count {
            for tabIDString in fs.tabIDs {
                if let tabID = UUID(uuidString: tabIDString) {
                    folders[index].tabIDs.append(tabID)
                }
            }
        }

        // Restore selection
        if let selectedIDString = session.selectedTabID,
           let selectedID = UUID(uuidString: selectedIDString),
           tabs.contains(where: { $0.id == selectedID }) {
            selectedTabID = selectedID
        } else {
            selectedTabID = tabs.first?.id
        }

        return true
    }

    // MARK: - Content Blocker

    private func loadContentBlocker() {
        guard let url = Bundle.main.url(forResource: "content-blocklist", withExtension: "json"),
              let json = try? String(contentsOf: url) else {
            loadDefaultBlockRules()
            return
        }

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "komo-blocker",
            encodedContentRuleList: json
        ) { [weak self] ruleList, error in
            if let ruleList = ruleList {
                DispatchQueue.main.async {
                    self?.contentRuleList = ruleList
                    for tab in self?.tabs ?? [] {
                        tab.webView.configuration.userContentController.add(ruleList)
                    }
                }
            }
        }
    }

    private func loadDefaultBlockRules() {
        let rules = """
        [
            {
                "trigger": { "url-filter": ".*", "resource-type": ["popup"] },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "googleadservices\\\\.com" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "doubleclick\\\\.net" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "google-analytics\\\\.com" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "facebook\\\\.com/tr" },
                "action": { "type": "block" }
            }
        ]
        """

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "komo-blocker-default",
            encodedContentRuleList: rules
        ) { [weak self] ruleList, error in
            if let ruleList = ruleList {
                DispatchQueue.main.async {
                    self?.contentRuleList = ruleList
                    for tab in self?.tabs ?? [] {
                        tab.webView.configuration.userContentController.add(ruleList)
                    }
                }
            }
        }
    }
}
