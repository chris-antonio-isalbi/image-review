// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FileOrganizerApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "FileOrganizerApp",
            targets: ["FileOrganizerApp"]
        ),
    ],
    dependencies: [
        // No external dependencies needed for this app
    ],
    targets: [
        .executableTarget(
            name: "FileOrganizerApp",
            dependencies: [],
            path: "Sources"
        ),
    ]
)