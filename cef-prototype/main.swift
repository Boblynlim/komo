// komo — minimal Swift ↔ CEF de-risk.
// Swift builds the NSWindow + content NSView; the C++/CEF side embeds a
// Chromium browser into that Swift-created view (native SetAsChild).
// Exposed to the Obj-C++/C++ side via C ABI (@_cdecl).

import AppKit

// Keep the window alive past the function return (CEF only holds the NSView).
final class KomoWindowHolder {
    static let shared = KomoWindowHolder()
    var window: NSWindow?
}

/// Build a titled window with an empty content view and return that view's
/// pointer so CEF can parent a browser into it. Must run on the main thread
/// (CEF calls this from OnContextInitialized, which is the macOS main thread).
@_cdecl("komo_build_browser_window")
public func komo_build_browser_window() -> UnsafeMutableRawPointer {
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
    let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false)
    window.title = "komo — Swift shell + Chromium engine"
    window.center()

    let contentView = NSView(frame: frame)
    contentView.autoresizingMask = [.width, .height]
    window.contentView = contentView

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    KomoWindowHolder.shared.window = window

    // Hand the raw NSView pointer to the C++ side (unretained — the holder owns it).
    return Unmanaged.passUnretained(contentView).toOpaque()
}
