import CurrentDomain
import Foundation

extension BundledGitCLIEngine {
  func validateInteractiveRebase(
    _ plan: InteractiveRebasePlan,
    against current: InteractiveRebasePlan
  ) throws {
    guard plan.upstreamOID == current.upstreamOID,
      plan.originalHeadOID == current.originalHeadOID
    else {
      throw GitEngineError.invalidRepository(
        "Branch history changed after the interactive rebase plan was loaded."
      )
    }
    let expectedOIDs = current.steps.map(\.oid)
    let plannedOIDs = plan.steps.map(\.oid)
    guard expectedOIDs.count == plannedOIDs.count,
      Set(expectedOIDs) == Set(plannedOIDs),
      Set(plannedOIDs).count == plannedOIDs.count
    else {
      throw GitEngineError.invalidOutput(
        "The interactive rebase plan must contain every commit exactly once."
      )
    }
    var hasRetainedCommit = false
    for step in plan.steps {
      guard isFullObjectID(step.oid) else {
        throw GitEngineError.invalidOutput(
          "The interactive rebase plan contained an invalid object ID."
        )
      }
      switch step.action {
      case .drop:
        continue
      case .squash:
        guard hasRetainedCommit else {
          throw GitEngineError.invalidOutput(
            "Squash must follow a retained commit."
          )
        }
      case .reword:
        guard
          let message = step.rewrittenMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines),
          !message.isEmpty
        else {
          throw GitEngineError.invalidOutput(
            "Every reword step requires a non-empty commit message."
          )
        }
        hasRetainedCommit = true
      case .pick:
        hasRetainedCommit = true
      }
    }
  }

  func createInteractiveRebaseState(
    plan: InteractiveRebasePlan,
    at location: RepositoryLocation
  ) throws -> URL {
    let fileManager = FileManager.default
    let stateURL = interactiveRebaseStateURL(at: location)
    if fileManager.fileExists(atPath: stateURL.path) {
      try fileManager.removeItem(at: stateURL)
    }
    do {
      try fileManager.createDirectory(
        at: stateURL,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )

      let todo =
        plan.steps
        .map { "\($0.action.rawValue) \($0.oid)" }
        .joined(separator: "\n") + "\n"
      try writeInteractiveRebaseFile(
        Data(todo.utf8),
        named: "todo",
        permissions: 0o600,
        in: stateURL
      )

      var editorOperations: [String] = []
      var messageIndex = 0
      for step in plan.steps {
        switch step.action {
        case .reword:
          let name = "message-\(messageIndex)"
          let message =
            step.rewrittenMessage!
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
          try writeInteractiveRebaseFile(
            Data(message.utf8),
            named: name,
            permissions: 0o600,
            in: stateURL
          )
          editorOperations.append("write:\(name)")
          messageIndex += 1
        case .squash:
          editorOperations.append("keep")
        case .pick, .drop:
          break
        }
      }
      try writeInteractiveRebaseFile(
        Data((editorOperations.joined(separator: "\n") + "\n").utf8),
        named: "editor-plan",
        permissions: 0o600,
        in: stateURL
      )
      try writeInteractiveRebaseFile(
        Data("0\n".utf8),
        named: "editor-index",
        permissions: 0o600,
        in: stateURL
      )

      let sequenceEditor = """
        #!/bin/sh
        set -eu
        /bin/cp "${CURRENT_REBASE_STATE:?}/todo" "$1"
        """
      try writeInteractiveRebaseFile(
        Data((sequenceEditor + "\n").utf8),
        named: "sequence-editor.sh",
        permissions: 0o700,
        in: stateURL
      )
      let messageEditor = """
        #!/bin/sh
        set -eu
        state="${CURRENT_REBASE_STATE:?}"
        index="$(/bin/cat "$state/editor-index")"
        line="$(/usr/bin/sed -n "$((index + 1))p" "$state/editor-plan")"
        /usr/bin/printf '%s\n' "$((index + 1))" > "$state/editor-index"
        case "$line" in
          write:*) /bin/cp "$state/${line#write:}" "$1" ;;
          keep) ;;
          *) exit 1 ;;
        esac
        """
      try writeInteractiveRebaseFile(
        Data((messageEditor + "\n").utf8),
        named: "message-editor.sh",
        permissions: 0o700,
        in: stateURL
      )
      return stateURL
    } catch {
      try? fileManager.removeItem(at: stateURL)
      throw GitEngineError.invalidOutput(
        "Could not prepare interactive rebase state: \(error.localizedDescription)"
      )
    }
  }

  func writeInteractiveRebaseFile(
    _ data: Data,
    named name: String,
    permissions: Int,
    in directory: URL
  ) throws {
    let url = directory.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions],
      ofItemAtPath: url.path
    )
  }

  func interactiveRebaseEnvironment(stateURL: URL) -> [String: String] {
    [
      "CURRENT_REBASE_STATE": stateURL.path,
      "GIT_SEQUENCE_EDITOR": shellQuoted(
        stateURL.appendingPathComponent("sequence-editor.sh").path
      ),
      "GIT_EDITOR": shellQuoted(
        stateURL.appendingPathComponent("message-editor.sh").path
      ),
    ]
  }

  func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  func interactiveRebaseStateURL(
    at location: RepositoryLocation
  ) -> URL {
    location.gitDirectoryURL.appendingPathComponent(
      "current-interactive-rebase",
      isDirectory: true
    )
  }

  func existingInteractiveRebaseState(
    at location: RepositoryLocation
  ) -> URL? {
    let url = interactiveRebaseStateURL(at: location)
    var isDirectory = ObjCBool(false)
    guard
      FileManager.default.fileExists(
        atPath: url.path,
        isDirectory: &isDirectory
      ), isDirectory.boolValue
    else {
      return nil
    }
    return url
  }

  func removeInteractiveRebaseState(
    at location: RepositoryLocation
  ) {
    guard let url = existingInteractiveRebaseState(at: location) else { return }
    try? FileManager.default.removeItem(at: url)
  }

}
