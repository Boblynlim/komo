import SwiftUI

// Hosts a tab's Chromium (CEF) browser view. The browser is parented into
// `tab.hostView`; we just place that view in the SwiftUI hierarchy and ask the
// tab to create its browser once it's on screen.
struct WebViewContainer: NSViewRepresentable {
    @ObservedObject var tab: Tab

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(tab.hostView, to: container)
        // Create the browser once the host view is in a window.
        DispatchQueue.main.async { tab.ensureBrowser() }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // Swap in the current tab's host view if it changed.
        if container.subviews.first !== tab.hostView {
            container.subviews.forEach { $0.removeFromSuperview() }
            attach(tab.hostView, to: container)
        }
        DispatchQueue.main.async { tab.ensureBrowser() }
    }

    private func attach(_ view: NSView, to container: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
