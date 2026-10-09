// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mac7Zip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Mac7Zip", targets: ["Mac7Zip"])
    ],
    targets: [
        .executableTarget(
            name: "Mac7Zip",
            path: "Sources/Mac7Zip"
        ),
        .testTarget(
            name: "Mac7ZipTests",
            dependencies: ["Mac7Zip"],
            path: "Tests/Mac7ZipTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
