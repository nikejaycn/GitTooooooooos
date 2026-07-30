// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "CurrentCore",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "current-benchmark", targets: ["CurrentBenchmarkCLI"]),
    .executable(name: "current", targets: ["CurrentCLI"]),
    .library(name: "CurrentDomain", targets: ["CurrentDomain"]),
    .library(name: "BenchmarkKit", targets: ["BenchmarkKit"]),
    .library(name: "CurrentCLIKit", targets: ["CurrentCLIKit"]),
    .library(name: "GitParsers", targets: ["GitParsers"]),
    .library(name: "GitEngine", targets: ["GitEngine"]),
    .library(name: "RepositoryModel", targets: ["RepositoryModel"]),
    .library(name: "OperationKit", targets: ["OperationKit"]),
    .library(name: "GraphKit", targets: ["GraphKit"]),
    .library(name: "DiffKit", targets: ["DiffKit"]),
    .library(name: "MergeKit", targets: ["MergeKit"]),
    .library(name: "CredentialKit", targets: ["CredentialKit"]),
    .library(name: "UpdateKit", targets: ["UpdateKit"]),
    .library(name: "CurrentUI", targets: ["CurrentUI"]),
    .library(name: "CurrentAppSupport", targets: ["CurrentAppSupport"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/sparkle-project/Sparkle.git",
      exact: "2.9.2"
    ),
    .package(
      url: "https://github.com/swiftlang/swift-subprocess.git",
      exact: "0.5.0"
    ),
    .package(
      url: "https://github.com/tree-sitter/swift-tree-sitter.git",
      exact: "0.25.0"
    ),
    .package(
      url: "https://github.com/alex-pinkus/tree-sitter-swift.git",
      revision: "0.7.3-with-generated-files"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-c.git",
      exact: "0.24.2"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-cpp.git",
      exact: "0.23.4"
    ),
    .package(
      url: "https://github.com/tree-sitter-grammars/tree-sitter-objc.git",
      exact: "3.0.2"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-javascript.git",
      exact: "0.23.1"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-typescript.git",
      exact: "0.23.2"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-python.git",
      exact: "0.23.6"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-go.git",
      exact: "0.25.0"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-rust.git",
      exact: "0.24.2"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-java.git",
      exact: "0.23.5"
    ),
    .package(
      url: "https://github.com/tree-sitter/tree-sitter-json.git",
      exact: "0.24.8"
    ),
    .package(
      url: "https://github.com/tree-sitter-grammars/tree-sitter-yaml.git",
      exact: "0.7.0"
    ),
  ],
  targets: [
    .target(name: "CurrentDomain"),
    .target(
      name: "BenchmarkKit",
      dependencies: ["CurrentDomain", "GitParsers", "GraphKit", "DiffKit"]
    ),
    .executableTarget(
      name: "CurrentBenchmarkCLI",
      dependencies: ["BenchmarkKit"]
    ),
    .target(
      name: "CurrentCLIKit",
      linkerSettings: [.linkedFramework("AppKit")]
    ),
    .executableTarget(
      name: "CurrentCLI",
      dependencies: ["CurrentCLIKit"]
    ),
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
      dependencies: ["CurrentDomain", "DiffKit", "GitEngine", "OperationKit"],
      linkerSettings: [
        .linkedFramework("CoreServices")
      ]
    ),
    .target(
      name: "OperationKit",
      dependencies: ["CurrentDomain", "DiffKit", "GitEngine"]
    ),
    .target(
      name: "GraphKit",
      dependencies: ["CurrentDomain"]
    ),
    .target(
      name: "DiffKit",
      dependencies: [
        "CurrentDomain",
        .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
        .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
        .product(name: "TreeSitterC", package: "tree-sitter-c"),
        .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
        .product(name: "TreeSitterObjc", package: "tree-sitter-objc"),
        .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
        .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
        .product(name: "TreeSitterPython", package: "tree-sitter-python"),
        .product(name: "TreeSitterGo", package: "tree-sitter-go"),
        .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
        .product(name: "TreeSitterJava", package: "tree-sitter-java"),
        .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
        .product(name: "TreeSitterYAML", package: "tree-sitter-yaml"),
      ]
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
      name: "UpdateKit",
      dependencies: [
        .product(name: "Sparkle", package: "Sparkle")
      ]
    ),
    .target(
      name: "CurrentUI",
      dependencies: ["CurrentDomain", "GraphKit", "DiffKit", "MergeKit"]
    ),
    .target(
      name: "CurrentAppSupport",
      dependencies: ["CurrentDomain", "CurrentUI", "DiffKit", "GraphKit"]
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
      dependencies: ["RepositoryModel", "GitEngine", "CurrentDomain", "DiffKit", "OperationKit"]
    ),
    .testTarget(
      name: "OperationKitTests",
      dependencies: ["OperationKit", "GitEngine", "CurrentDomain"]
    ),
    .testTarget(
      name: "DiffKitTests",
      dependencies: ["DiffKit", "CurrentDomain"]
    ),
    .testTarget(
      name: "GraphKitTests",
      dependencies: ["GraphKit", "CurrentDomain"]
    ),
    .testTarget(
      name: "CurrentDomainTests",
      dependencies: ["CurrentDomain"]
    ),
    .testTarget(
      name: "CurrentCLIKitTests",
      dependencies: ["CurrentCLIKit"]
    ),
    .testTarget(
      name: "BenchmarkKitTests",
      dependencies: ["BenchmarkKit"]
    ),
    .testTarget(
      name: "CurrentUITests",
      dependencies: ["CurrentUI"]
    ),
    .testTarget(
      name: "CurrentAppSupportTests",
      dependencies: ["CurrentAppSupport", "CurrentDomain", "CurrentUI", "DiffKit", "GraphKit"]
    ),
    .testTarget(
      name: "MergeKitTests",
      dependencies: ["MergeKit"]
    ),
    .testTarget(
      name: "UpdateKitTests",
      dependencies: ["UpdateKit"]
    ),
  ]
)
