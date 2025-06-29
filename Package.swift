// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SwiftOCRwithUI",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "SwiftOCRwithUI", targets: ["SwiftOCRwithUI"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SwiftOCRwithUI",
            dependencies: []
        )
    ]
)
