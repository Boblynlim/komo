import SwiftUI
import AppKit
import KomoCEF

extension Color {
    // #E866D4
    static let kPink = Color(red: 0.91, green: 0.40, blue: 0.83)
}

extension ShapeStyle where Self == Color {
    static var kPink: Color { .kPink }
}

// Initializes the Chromium engine (CEF) at startup, before any browser/tab is
// created. applicationWillFinishLaunching runs before the UI appears.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if komo_cef_initialize() {
            NSLog("komo: Chromium engine (CEF) v%s initialized", komo_cef_version())
        } else {
            NSLog("komo: CEF failed to initialize")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        komo_cef_shutdown()
    }
}

@main
struct komoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var tabManager = TabManager()
    @StateObject private var linkStore = LinkStore()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var pulseEngine = PulseEngine()

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
