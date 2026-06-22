# cef-prototype — Swift + Chromium (CEF) de-risk

Proof that komo can be built the way Arc is: a **native Swift UI** hosting the
**Chromium engine**, instead of WebKit (WKWebView) or an extension.

`main.swift` builds an `NSWindow` + content `NSView` in Swift; the C++/Obj-C++
side (adapted from CEF's `cefsimple`) parents a real Chromium browser into that
Swift-created view via `CefWindowInfo::SetAsChild`. Confirmed working on
arm64 macOS — full multiprocess Chromium (GPU + renderer + network) renders a
page inside the Swift window, and the whole thing builds in ~seconds (the engine
is prebuilt).

## What's here
- `main.swift` — Swift UI layer (`komo_build_browser_window`, `@_cdecl`)
- `simple_app.cc` — CefApp; embeds the browser into the Swift view
- `simple_handler.*`, `cefsimple_mac.mm`, `process_helper_mac.cc` — CEF plumbing (from cefsimple, BSD)
- `CMakeLists.txt` — builds a Swift+C++ target, bundles the CEF framework + helper apps + signing
- `mac/` — Info.plist templates, icon, MainMenu.xib

## Build (needs the CEF SDK — NOT committed, ~280 MB)
1. Download the standard CEF binary distribution for macosarm64 from
   https://cef-builds.spotifycdn.com/ (this prototype used CEF 149 / Chromium 149).
2. Extract it; drop this `swiftcef`-style folder into `cef/tests/swiftcef/`,
   add `add_subdirectory(tests/swiftcef)` to the CEF tree's top `CMakeLists.txt`.
3. `cd cef && mkdir build && cd build && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 .. && ninja swiftcef`
4. `codesign --force --deep --sign - tests/swiftcef/Release/swiftcef.app && open tests/swiftcef/Release/swiftcef.app`

## Next
Port this into the real komo app: replace `WebViewContainer`'s `WKWebView`
with a CEF-backed `NSView`, wire it to `Tab`/`TabManager`, and bundle CEF with
komo's build. (komo, being a SwiftUI app that owns its run loop, will use CEF's
external message pump rather than `CefRunMessageLoop`.)
