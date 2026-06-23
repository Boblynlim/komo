import SwiftUI

struct BrowserWindow: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var linkStore: LinkStore
    @State private var showSavePanel = false
    @State private var showLinkLibrary = false
    @State private var showPulse = false

    var body: some View {
        NavigationSplitView(columnVisibility: .init(
            get: { tabManager.isSidebarVisible ? .all : .detailOnly },
            set: { tabManager.isSidebarVisible = ($0 != .detailOnly) }
        )) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 140, ideal: 180, max: 280)
        } detail: {
            if showPulse {
                PulseView()
                    .toolbar { browserToolbar }
            } else if showLinkLibrary {
                LinkLibraryView()
                    .toolbar { browserToolbar }
            } else {
                ZStack {
                    if let tab = tabManager.selectedTab {
                        if tab.url == nil {
                            EmptyStateView()
                        } else {
                            WebViewContainer(tab: tab)
                        }
                    } else {
                        EmptyStateView()
                    }
                }
                .toolbar { browserToolbar }
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $showSavePanel) {
            if let tab = tabManager.selectedTab {
                SaveLinkPanel(
                    isPresented: $showSavePanel,
                    url: tab.url?.absoluteString ?? "",
                    title: tab.title
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveCurrentLink)) { _ in
            if tabManager.selectedTab?.url != nil {
                showSavePanel = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLinkLibrary)) { _ in
            showLinkLibrary.toggle()
            if showLinkLibrary { showPulse = false }
        }
        .overlay(alignment: .bottomTrailing) {
            DownloadPopupCard()
                .padding(16)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCommandBar)) { _ in
            CommandBarController.shared.toggle()
        }
        .onAppear {
            // The command bar lives in its own floating key window (NSPanel),
            // not a same-window overlay — an embedded CEF view would otherwise
            // swallow all of its mouse/keyboard input.
            CommandBarController.shared.configure(tabManager: tabManager, linkStore: linkStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: .togglePulse)) { _ in
            showPulse.toggle()
            if showPulse { showLinkLibrary = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissOverlays)) { _ in
            showPulse = false
            showLinkLibrary = false
        }
    }

    @ToolbarContentBuilder
    var browserToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            NavButtons()
        }
        ToolbarItem(placement: .principal) {
            URLPill()
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("komo")
                .font(.system(size: 48, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
            Text("your corner of the internet")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
