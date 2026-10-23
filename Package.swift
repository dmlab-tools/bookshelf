// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bookshelf",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Bookshelf", targets: ["Bookshelf"]),
    ],
    targets: [
        .target(name: "LibraryCore"),
        .executableTarget(name: "Bookshelf", dependencies: ["LibraryCore"]),
        .testTarget(name: "LibraryCoreTests", dependencies: ["LibraryCore"]),
    ]
)
