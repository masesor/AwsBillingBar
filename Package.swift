// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AwsBillingBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "AwsBillingBar", targets: ["AwsBillingBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.5.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.10.0"),
    ],
    targets: [
        // Core library with data models and AWS integration
        .target(
            name: "AwsBillingBarCore",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AwsBillingBarCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),

        // Main macOS app
        .executableTarget(
            name: "AwsBillingBar",
            dependencies: [
                "AwsBillingBarCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/AwsBillingBar",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),

        // Tests
        .testTarget(
            name: "AwsBillingBarTests",
            dependencies: ["AwsBillingBarCore"],
            path: "Tests/AwsBillingBarTests"
        ),
    ]
)
