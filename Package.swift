// swift-tools-version: 5.9
import PackageDescription

// CEF SDK location (downloaded separately; see cef-prototype/README.md).
// TODO: make this relative / configurable once the integration stabilizes.
let cefRoot = "/Users/jazulynn/src/tries/browser/cef-proof/cef"
let cefWrapper = "/Users/jazulynn/src/tries/browser/cef-proof/cef/build/libcef_dll_wrapper/libcef_dll_wrapper.a"

let package = Package(
    name: "komo",
    platforms: [.macOS(.v14)],
    targets: [
        // Objective-C++ bridge to the Chromium engine (CEF).
        .target(
            name: "KomoCEF",
            path: "KomoCEF",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-I\(cefRoot)", "-std=c++20", "-fobjc-arc"])
            ]
        ),
        .executableTarget(
            name: "komo",
            dependencies: ["KomoCEF"],
            path: "komo",
            exclude: ["komo.entitlements"],
            resources: [
                .copy("Assets.xcassets"),
            ],
            linkerSettings: [
                .unsafeFlags([cefWrapper, "-lc++"])
            ]
        ),
    ]
)
