import SwiftUI

struct BrowserCommands: Commands {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var linkStore: LinkStore

    var body: some Commands {
        // Replace default New Window with New Tab
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                tabManager.createNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Close Tab") {
                tabManager.closeCurrentTab()
            }
            .keyboardShortcut("w", modifiers: .command)

            Divider()

            Button("Focus URL Bar") {
                NotificationCenter.default.post(name: .focusURLBar, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("Save Link") {
                NotificationCenter.default.post(name: .saveCurrentLink, object: nil)
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Toggle Saved Links") {
                NotificationCenter.default.post(name: .toggleLinkLibrary, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button("Command Bar") {
                NotificationCenter.default.post(name: .toggleCommandBar, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button(tabManager.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                tabManager.toggleSidebar()
            }
            .keyboardShortcut("\\", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let focusURLBar = Notification.Name("focusURLBar")
    static let saveCurrentLink = Notification.Name("saveCurrentLink")
    static let toggleLinkLibrary = Notification.Name("toggleLinkLibrary")
    static let toggleCommandBar = Notification.Name("toggleCommandBar")
}
