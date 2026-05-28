// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NomiPetApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NomiPetApp", targets: ["NomiPetApp"])
    ],
    targets: [
        .executableTarget(
            name: "NomiPetApp",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
