// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Cliplight",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Cliplight", targets: ["Cliplight"])],
    targets: [
        .executableTarget(name: "Cliplight", linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon")])
    ]
)
