// swift-tools-version: 5.9

// Swift Playgrounds app package. Open this folder (CoreStudio.swiftpm) in
// Swift Playgrounds on iPad and press Run.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "CoreStudio",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "CoreStudio",
            targets: ["AppModule"],
            bundleIdentifier: "com.alaadin.corestudio",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .movieReel),
            accentColor: .presetColor(.purple),
            supportedDeviceFamilies: [
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
