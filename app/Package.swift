// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Decks",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Decks",
            path: "Sources/Decks"
        )
    ]
)
