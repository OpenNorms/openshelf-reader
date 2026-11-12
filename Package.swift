// swift-tools-version:5.9
import PackageDescription

// ReaderCore is the platform-independent engine of OpenShelf Reader:
// KB loading (OpenShelf kb.yaml + frontmatter), markdown -> HTML
// rendering, composition of several KBs into one, themes, and the
// git-sync contract. It depends only on Foundation, so it builds and
// tests anywhere Swift runs. The iOS app target (see project.yml)
// links it and adds SwiftUI + WKWebView + the libgit2 sync engine.
let package = Package(
    name: "OpenShelfReader",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
    ],
    targets: [
        .target(name: "ReaderCore"),
        .testTarget(
            name: "ReaderCoreTests",
            dependencies: ["ReaderCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
