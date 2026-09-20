// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Talkback",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Talkback", targets: ["Talkback"])
    ],
    targets: [
        .executableTarget(
            name: "Talkback",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech")
            ]
        ),
        .testTarget(name: "TalkbackTests", dependencies: ["Talkback"])
    ],
    swiftLanguageModes: [.v6]
)
