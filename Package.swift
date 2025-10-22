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
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "FileOrganizerApp",
            dependencies: [
                .product(name: "Swifter", package: "swifter")
            ],
            path: "Sources"
        ),
    ]
)