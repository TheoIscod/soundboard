// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "Soundboard",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "SoundboardCore"),
    .executableTarget(
      name: "Soundboard",
      dependencies: ["SoundboardCore"]
    ),
    .testTarget(
      name: "SoundboardCoreTests",
      dependencies: ["SoundboardCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
