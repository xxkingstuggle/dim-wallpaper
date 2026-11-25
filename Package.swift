// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DimWallpaper",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "DimWallpaperCore", targets: ["DimWallpaperCore"]),
        .executable(name: "DimWallpaper", targets: ["DimWallpaper"]),
    ],
    targets: [
        .target(
            name: "DimWallpaperCore",
            path: "Sources/DimWallpaperCore"
        ),
        .executableTarget(
            name: "DimWallpaper",
            dependencies: ["DimWallpaperCore"],
            path: "Sources/DimWallpaperApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "DimWallpaperCoreTests",
            dependencies: ["DimWallpaperCore"],
            path: "Tests/DimWallpaperCoreTests"
        ),
    ]
)
