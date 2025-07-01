// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SwiftOCRwithUI",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "SwiftOCRwithUI", targets: ["SwiftOCRwithUI"]),
        .executable(name: "DateRenamer", targets: ["DateRenamer"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SwiftOCRwithUI",
            dependencies: []
        ),
        .executableTarget(
            name: "DateRenamer",
            dependencies: []
        ),
    ]
)
