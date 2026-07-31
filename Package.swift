// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Shark",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Shark", targets: ["Shark"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "Shark",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/Shark"
        )
    ]
)
