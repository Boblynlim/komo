import SwiftUI
import AppKit

// A borderless floating panel that CAN become key, so the command bar inside it
// receives all keyboard + mouse events — independent of the CEF web view in the
// main window. (As a same-window SwiftUI overlay, the embedded CEF native view
// captures the events instead and the command bar is dead.)
final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class CommandBarController: NSObject, NSWindowDelegate {
    static let shared = CommandBarController()

    private var panel: CommandPanel?
    private weak var tabManager: TabManager?
    private weak var linkStore: LinkStore?
    // komo drives its own run loop for CEF, which starves this separate panel's
    // automatic display pass — so the SwiftUI content re-renders but never
    // repaints. Force a flush while the panel is visible.
    private var displayTimer: Timer?
    // SwiftUI's onKeyPress for arrows/Tab is unreliable with a focused field,
    // so we intercept those keys at the app level and drive selection directly.
    let selection = CommandBarSelection()
    private var keyMonitor: Any?

    func configure(tabManager: TabManager, linkStore: LinkStore) {
        self.tabManager = tabManager
        self.linkStore = linkStore
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard let tabManager, let linkStore else { return }
        selection.index = 0
        let panel = ensurePanel()

        let host = CommandBarHost(selection: selection, onDismiss: { [weak self] in self?.hide() })
            .environmentObject(tabManager)
            .environmentObject(linkStore)

        let hosting = NSHostingView(rootView: host)
        hosting.setFrameSize(hosting.fittingSize)
        panel.setContentSize(hosting.fittingSize)
        panel.contentView = hosting

        position(panel)
        panel.makeKeyAndOrderFront(nil)

        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak panel] _ in
            panel?.contentView?.displayIfNeeded()
        }

        // Intercept ↑/↓/Tab at the app level (letters/Enter pass through).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            switch event.keyCode {
            case 125: self.selection.moveDown(); return nil   // down arrow
            case 126: self.selection.moveUp(); return nil     // up arrow
            case 48:                                           // tab
                event.modifierFlags.contains(.shift) ? self.selection.moveUp() : self.selection.moveDown()
                return nil
            default:
                return event
            }
        }
    }

    func hide() {
        displayTimer?.invalidate()
        displayTimer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> CommandPanel {
        if let panel { return panel }
        let p = CommandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.delegate = self
        panel = p
        return p
    }

    private func position(_ panel: NSPanel) {
        let ref = NSApp.mainWindow ?? NSApp.windows.first { $0 !== panel }
        guard let frame = ref?.frame else { return }
        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 100
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // Dismiss when the user clicks away (panel loses key).
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}

// Shared selection state, driven by the app-level key monitor and observed by
// the command bar for highlighting.
@MainActor
final class CommandBarSelection: ObservableObject {
    @Published var index = 0
    // The view keeps this current so the monitor can clamp.
    var count = 0

    func moveDown() {
        guard count > 0 else { return }
        index = min(count - 1, index + 1)
    }
    func moveUp() {
        index = max(0, index - 1)
    }
}

// Bridges CommandBar's `isPresented` binding to the panel's dismiss.
private struct CommandBarHost: View {
    @ObservedObject var selection: CommandBarSelection
    let onDismiss: () -> Void
    @State private var present = true

    var body: some View {
        CommandBar(selection: selection, isPresented: Binding(
            get: { present },
            set: { newValue in
                present = newValue
                if !newValue { onDismiss() }
            }
        ))
        .fixedSize()
    }
}
