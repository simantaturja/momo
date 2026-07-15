// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Momo",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "MomoCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Momo",
            dependencies: ["MomoCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Momo/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "MomoCoreTests",
            dependencies: ["MomoCore"]
        ),
    ]
)
