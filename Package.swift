// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerrariumMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TerrariumCore", targets: ["TerrariumCore"]),
        .executable(name: "TerrariumMenuBar", targets: ["TerrariumMenuBar"]),
        .executable(name: "TerrariumCoreTestRunner", targets: ["TerrariumCoreTestRunner"])
    ],
    targets: [
        .target(
            name: "TerrariumCore",
            resources: [
                .copy("Resources/Locales")
            ]
        ),
        .executableTarget(
            name: "TerrariumMenuBar",
            dependencies: ["TerrariumCore"],
            exclude: ["Resources/AppIcon.icns"],
            resources: [
                .copy("Resources/Pixel")
            ]
        ),
        .executableTarget(
            name: "TerrariumCoreTestRunner",
            dependencies: ["TerrariumCore"]
        )
    ]
)
