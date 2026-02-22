// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SamsWorkoutNative",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "WorkoutDesktopApp",
            targets: ["WorkoutDesktopApp"]
        ),
        .library(
            name: "WorkoutCore",
            targets: ["WorkoutCore"]
        ),
        .library(
            name: "WorkoutIntegrations",
            targets: ["WorkoutIntegrations"]
        ),
        .library(
            name: "WorkoutPersistence",
            targets: ["WorkoutPersistence"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "WorkoutCore"
        ),
        .target(
            name: "WorkoutIntegrations",
            dependencies: ["WorkoutCore"]
        ),
        .target(
            name: "WorkoutPersistence",
            dependencies: [
                "WorkoutCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "WorkoutDesktopApp",
            dependencies: [
                "WorkoutCore",
                "WorkoutIntegrations",
                "WorkoutPersistence",
            ]
        ),
        .testTarget(
            name: "WorkoutCoreTests",
            dependencies: ["WorkoutCore"]
        ),
        .testTarget(
            name: "WorkoutIntegrationsTests",
            dependencies: ["WorkoutIntegrations"]
        ),
        .testTarget(
            name: "WorkoutPersistenceTests",
            dependencies: ["WorkoutPersistence"]
        ),
        .testTarget(
            name: "WorkoutDesktopAppTests",
            dependencies: ["WorkoutDesktopApp"]
        ),
    ]
)
