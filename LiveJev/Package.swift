// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiveJev",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LiveJev", targets: ["LiveJev"])
    ],
    targets: [
        .executableTarget(
            name: "LiveJev",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
