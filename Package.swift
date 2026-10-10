// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mac7zip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Mac7zip", targets: ["Mac7zip"])
    ],
    targets: [
        .executableTarget(
            name: "Mac7zip",
            path: "Sources/Mac7zip"
        ),
        .testTarget(
            name: "Mac7zipTests",
            dependencies: ["Mac7zip"],
            path: "Tests/Mac7zipTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
