// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NagaControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NagaKit", linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("IOUSBHost")]),
        .executableTarget(name: "NagaControl", dependencies: ["NagaKit"]),
    ]
)
