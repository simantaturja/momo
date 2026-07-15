// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pastal",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "PastalCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Pastal",
            dependencies: ["PastalCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Pastal/Info.plist",
                ])
            ]
        ),
        .testTarget(
            name: "PastalCoreTests",
            dependencies: ["PastalCore"]
        ),
    ]
)
