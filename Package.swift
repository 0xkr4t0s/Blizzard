// swift-tools-version: 6.2
// Swift 6 language mode (complete strict concurrency) is the default for tools 6.x.
// Package targets must not enable default MainActor isolation (ARCHITECTURE §4).
import PackageDescription

let package = Package(
    name: "Blizzard",
    // Minimum macOS is still open (SPEC NFR-009). 15.0 is the current proposal.
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BlizzardCore", targets: ["BlizzardCore"]),
        .executable(name: "blizzard-probe", targets: ["BlizzardProbe"]),
    ],
    targets: [
        // C++17 façade over bosectl's headers. Swift sees only include/bmap_shim.h (ADR-0002).
        // No vendored .cpp is compiled: the shim includes individual bosectl headers only.
        .target(
            name: "BMAPShim",
            exclude: ["AGENTS.md", "CLAUDE.md"],
            publicHeadersPath: "include",
            cxxSettings: [.headerSearchPath("../../Vendor/bosectl/cpp/src")]
        ),
        // The only target allowed to import IOBluetooth.
        .target(
            name: "RFCOMMTransport",
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .target(
            name: "BlizzardCore",
            dependencies: ["BMAPShim", "RFCOMMTransport"],
            exclude: ["AGENTS.md", "CLAUDE.md"]
        ),
        .executableTarget(
            name: "BlizzardProbe",
            dependencies: ["BlizzardCore"]
        ),
        .testTarget(
            name: "BMAPShimTests",
            dependencies: ["BMAPShim"]
        ),
        .testTarget(
            name: "BlizzardCoreTests",
            dependencies: ["BlizzardCore"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
