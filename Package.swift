// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Charms",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Charms", targets: ["Charms"])],
    targets: [
        // Pure logic: catalogue model, search, placement, session and trigger
        // state, persistence. No AppKit, so everything here is unit-testable.
        .target(name: "CharmsCore"),

        // The menu-bar app: AppKit/SwiftUI, Accessibility, hot key, insertion.
        .executableTarget(name: "Charms", dependencies: ["CharmsCore"]),

        // Development tools. Neither ships inside Charms.app.
        .target(name: "CharmsCatalogBuilder", dependencies: ["CharmsCore"]),
        .executableTarget(name: "CharmsCatalogTool", dependencies: ["CharmsCatalogBuilder"]),
        .executableTarget(name: "CharmsHarness"),

        .testTarget(name: "CharmsCoreTests", dependencies: ["CharmsCore"]),
        .testTarget(name: "CharmsCatalogBuilderTests", dependencies: ["CharmsCatalogBuilder"])
    ],
    swiftLanguageModes: [.v5]
)
