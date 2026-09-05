// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Resume",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ResumeCore", targets: ["ResumeCore"]),
        .executable(name: "Resume", targets: ["Resume"]),
    ],
    targets: [
        .target(name: "ResumeCore"),
        .executableTarget(name: "Resume", dependencies: ["ResumeCore"]),
        .testTarget(name: "ResumeCoreTests", dependencies: ["ResumeCore"]),
    ]
)
