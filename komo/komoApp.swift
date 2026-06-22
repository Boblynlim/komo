import SwiftUI
import KomoCEF

extension Color {
    // #E866D4
    static let kPink = Color(red: 0.91, green: 0.40, blue: 0.83)
}

extension ShapeStyle where Self == Color {
    static var kPink: Color { .kPink }
}

@main
struct komoApp: App {
    @StateObject private var tabManager = TabManager()
    @StateObject private var linkStore = LinkStore()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var pulseEngine = PulseEngine()

    init() {
        // Proves komo links + calls the Chromium (CEF) bridge.
        print("komo: Chromium engine (CEF) v\(String(cString: komo_cef_version()))")
    }

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
                .environmentObject(tabManager)
                .environmentObject(linkStore)
                .environmentObject(downloadManager)
                .environmentObject(pulseEngine)
                .frame(minWidth: 800, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    tabManager.saveSession()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            BrowserCommands(tabManager: tabManager, linkStore: linkStore)
        }
    }
}
