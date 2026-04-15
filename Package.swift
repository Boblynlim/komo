// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "komo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "komo",
            path: "komo",
            exclude: ["komo.entitlements"],
            resources: [
                .copy("Assets.xcassets"),
            ]
        ),
    ]
)
