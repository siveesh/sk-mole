// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SKMole",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SKMoleShared",
            targets: ["SKMoleShared"]
        ),
        .executable(
            name: "SKMoleApp",
            targets: ["SKMoleApp"]
        ),
        .executable(
            name: "SKMolePrivilegedHelper",
            targets: ["SKMolePrivilegedHelper"]
        ),
        .executable(
            name: "SKMoleMenuBarHelper",
            targets: ["SKMoleMenuBarHelper"]
        )
    ],
    targets: [
        .target(
            name: "SKMoleShared",
            path: "Sources/SKMoleShared"
        ),
        .executableTarget(
            name: "SKMoleApp",
            dependencies: ["SKMoleShared"],
            path: "Sources/SKMoleApp"
        ),
        .executableTarget(
            name: "SKMolePrivilegedHelper",
            dependencies: ["SKMoleShared"],
            path: "Sources/SKMolePrivilegedHelper"
        ),
        .executableTarget(
            name: "SKMoleMenuBarHelper",
            dependencies: ["SKMoleShared"],
            path: "Sources/SKMoleMenuBarHelper"
        ),
        .testTarget(
            name: "SKMoleAppTests",
            dependencies: ["SKMoleApp", "SKMoleShared"],
            path: "Tests/SKMoleAppTests"
        )
    ]
)
