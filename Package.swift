// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Resume",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "ResumeCore", targets: ["ResumeCore"]),
    .executable(name: "Resume", targets: ["Resume"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/socketio/socket.io-client-swift", .upToNextMinor(from: "16.1.1"))
  ],
  targets: [
    .target(name: "ResumeCore"),
    .executableTarget(
      name: "Resume",
      dependencies: ["ResumeCore", .product(name: "SocketIO", package: "socket.io-client-swift")]),
    .testTarget(name: "ResumeCoreTests", dependencies: ["ResumeCore"]),
  ]
)
