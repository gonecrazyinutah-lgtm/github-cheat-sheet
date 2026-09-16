// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Finding",
    platforms: [.iOS(.v17)],
    products: [.library(name: "Finding", targets: ["Finding"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "7.1.0")
    ],
    targets: [
        .target(
            name: "Finding",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS")
            ],
            path: ".",
            sources: ["Managers", "Models", "ContentView.swift", "PhotoRecoveryApp.swift"]
        )
    ]
)
