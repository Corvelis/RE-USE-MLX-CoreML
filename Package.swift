// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ReuseKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ReuseKit", targets: ["ReuseKit"]),
        .library(name: "ReusePlayback", targets: ["ReusePlayback"]),
        .library(name: "ReuseModelAssets", targets: ["ReuseModelAssets"]),
        .executable(name: "reuse-probe", targets: ["ReuseProbe"]),
    ],
    dependencies: [.package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.33.0")],
    targets: [
        .target(name: "ReuseModelAssets"),
        .testTarget(name: "ReuseModelAssetsTests", dependencies: ["ReuseModelAssets"]),
        .target(name: "CReusePlayback"),
        .target(name: "ReusePlayback", dependencies: ["CReusePlayback"]),
        .target(name: "ReuseKit", dependencies: [
            .product(name: "MLX", package: "mlx-swift"),
            .product(name: "MLXNN", package: "mlx-swift"),
            .product(name: "MLXFast", package: "mlx-swift"),
            .product(name: "MLXFFT", package: "mlx-swift"),
        ]),
        .executableTarget(name: "ReuseProbe", dependencies: ["ReuseKit"]),
        .testTarget(name: "ReuseKitTests", dependencies: ["ReuseKit"]),
        .testTarget(name: "ReusePlaybackTests", dependencies: ["ReusePlayback", "CReusePlayback"]),
    ],
    swiftLanguageModes: [.v5]
)
