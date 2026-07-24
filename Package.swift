// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "CurrentCore",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "CurrentDomain", targets: ["CurrentDomain"]),
    .library(name: "GitParsers", targets: ["GitParsers"]),
    .library(name: "GitEngine", targets: ["GitEngine"]),
    .library(name: "RepositoryModel", targets: ["RepositoryModel"]),
    .library(name: "OperationKit", targets: ["OperationKit"]),
    .library(name: "GraphKit", targets: ["GraphKit"]),
    .library(name: "DiffKit", targets: ["DiffKit"]),
    .library(name: "MergeKit", targets: ["MergeKit"]),
    .library(name: "CredentialKit", targets: ["CredentialKit"]),
    .library(name: "CurrentUI", targets: ["CurrentUI"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/swiftlang/swift-subprocess.git",
      exact: "0.5.0"
    )
  ],
  targets: [
    .target(name: "CurrentDomain"),
    .target(name: "GitParsers"),
    .target(
      name: "GitEngine",
      dependencies: [
        "CurrentDomain",
        "DiffKit",
        "GitParsers",
        .product(name: "Subprocess", package: "swift-subprocess"),
      ]
    ),
    .target(
      name: "RepositoryModel",
      dependencies: ["CurrentDomain", "DiffKit", "GitEngine"]
    ),
    .target(
      name: "OperationKit",
      dependencies: ["CurrentDomain", "GitEngine"]
    ),
    .target(
      name: "GraphKit",
      dependencies: ["CurrentDomain"]
    ),
    .target(
      name: "DiffKit",
      dependencies: ["CurrentDomain"]
    ),
    .target(
      name: "MergeKit",
      dependencies: ["CurrentDomain", "DiffKit", "OperationKit"]
    ),
    .target(
      name: "CredentialKit",
      dependencies: ["CurrentDomain"]
    ),
    .target(
      name: "CurrentUI",
      dependencies: ["CurrentDomain", "GraphKit", "DiffKit"]
    ),
    .testTarget(
      name: "GitParsersTests",
      dependencies: ["GitParsers"]
    ),
    .testTarget(
      name: "GitEngineTests",
      dependencies: ["GitEngine", "CurrentDomain", "DiffKit"]
    ),
    .testTarget(
      name: "RepositoryModelTests",
      dependencies: ["RepositoryModel", "GitEngine", "CurrentDomain", "DiffKit"]
    ),
    .testTarget(
      name: "OperationKitTests",
      dependencies: ["OperationKit", "GitEngine", "CurrentDomain"]
    ),
    .testTarget(
      name: "DiffKitTests",
      dependencies: ["DiffKit", "CurrentDomain"]
    ),
  ]
)
