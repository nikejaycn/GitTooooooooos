import CurrentDomain
import DiffKit
import Foundation
import GitEngine

extension OperationPlanner {
  public static func patch(
    fileURL: URL,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    try OperationPlan(
      kind: "patch.apply",
      title: "Apply patch",
      repositoryGeneration: generation,
      preconditions: [
        "The patch is a regular file no larger than 64 MB",
        "Git verifies the patch applies cleanly to both the index and working tree",
      ],
      commands: [
        .git(
          GitCommand(
            rawArguments: ["apply", "--index", "--"].map { Array($0.utf8) }
              + [Array(fileURL.path.utf8)],
            workingDirectory: location.worktreeURL
          )
        )
      ],
      workingTreeImpact: .indexAndWorktree,
      risk: .localSafe
    )
  }

  public static func hunk(
    source: DiffSource,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    let isUnstage = source == .staged
    let arguments =
      ["apply", "--cached", "--recount", "--whitespace=nowarn"]
      + (isUnstage ? ["--reverse"] : [])
      + ["-"]
    return try OperationPlan(
      kind: isUnstage ? "index.unstage-hunk" : "index.stage-hunk",
      title: isUnstage ? "Unstage selected hunk" : "Stage selected hunk",
      repositoryGeneration: generation,
      preconditions: [
        "The selected patch is non-empty, at most 16 MB, and has a diff header",
        "Git applies the patch to the index from standard input",
      ],
      commands: [
        .git(
          GitCommand(
            arguments: arguments,
            workingDirectory: location.worktreeURL
          )
        )
      ],
      workingTreeImpact: .indexOnly,
      risk: .localSafe
    )
  }

  public static func discardHunk(
    path: GitPath,
    generation: RepositoryGeneration,
    at location: RepositoryLocation
  ) throws -> OperationPlan {
    try OperationPlan(
      kind: "worktree.discard-hunk",
      title: "Discard selected working-tree patch",
      repositoryGeneration: generation,
      preconditions: [
        "The patch is non-empty, at most 16 MB, and belongs to the selected path",
        "The original file is retained as a blob behind a hidden recovery reference",
        "Undo verifies the post-discard worktree blob before restoring the original bytes",
      ],
      commands: [
        .git(
          GitCommand(
            rawArguments: ["hash-object", "--no-filters", "-w", "--"].map { Array($0.utf8) }
              + [path.rawBytes],
            workingDirectory: location.worktreeURL
          )
        ),
        .git(
          GitCommand(
            arguments: [
              "update-ref", "refs/current/undo/<generated-id>", "<original-blob-oid>",
            ],
            workingDirectory: location.worktreeURL
          )
        ),
        .git(
          GitCommand(
            arguments: [
              "apply", "--reverse", "--recount", "--whitespace=nowarn", "-",
            ],
            workingDirectory: location.worktreeURL
          )
        ),
      ],
      affectedRefs: ["refs/current/undo/<generated-id>"],
      workingTreeImpact: .worktreeOnly,
      risk: .localDestructive,
      recoveryStrategy: .gitReference
    )
  }
}
