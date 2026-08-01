import CurrentDomain
import DiffKit
import SwiftUI

struct PendingMergeRequest {
  let branch: String
  let squash: Bool
}

struct PendingRemoteBranchDeletion {
  let reference: GitReference
  let target: RemoteBranchCheckoutTarget
}

struct PartialDiscardRequest {
  let document: DiffDocument
  let hunk: DiffHunk
  let lineIndex: Int?
}

struct BranchDialogsModifier: ViewModifier {
  @Binding var branchToRename: GitReference?
  @Binding var renamedBranchName: String
  @Binding var pendingBranchDeletion: GitReference?
  let renameBranch: (String, String) -> Void
  let deleteBranch: (String) -> Void

  func body(content: Content) -> some View {
    content
      .alert(
        "Rename Branch",
        isPresented: Binding(
          get: { branchToRename != nil },
          set: { if !$0 { branchToRename = nil } }
        )
      ) {
        TextField("New branch name", text: $renamedBranchName)
        Button("Rename") {
          if let branchToRename {
            renameBranch(branchToRename.shortName, renamedBranchName)
          }
          branchToRename = nil
        }
        .disabled(
          renamedBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || renamedBranchName == branchToRename?.shortName
        )
        Button("Cancel", role: .cancel) {
          branchToRename = nil
        }
      } message: {
        Text("This renames the local branch. Remote branches are unchanged.")
      }
      .confirmationDialog(
        "Delete \(pendingBranchDeletion?.shortName ?? "this branch")?",
        isPresented: Binding(
          get: { pendingBranchDeletion != nil },
          set: { if !$0 { pendingBranchDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Delete Merged Branch", role: .destructive) {
          if let pendingBranchDeletion {
            deleteBranch(pendingBranchDeletion.shortName)
          }
          pendingBranchDeletion = nil
        }
        Button("Cancel", role: .cancel) {
          pendingBranchDeletion = nil
        }
      } message: {
        Text(
          "GitCurrent uses Git's safe delete and refuses if the branch contains unmerged commits."
        )
      }
  }
}

struct RemoteBranchDeletionDialogModifier: ViewModifier {
  @Binding var pending: PendingRemoteBranchDeletion?
  @State private var finalConfirmation: PendingRemoteBranchDeletion?
  let delete: (String, String, String) -> Void

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        "Delete remote branch \(pending?.reference.shortName ?? "")?",
        isPresented: Binding(
          get: { pending != nil },
          set: { if !$0 { pending = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("Continue") {
          finalConfirmation = pending
          pending = nil
        }
        Button("Cancel", role: .cancel) {
          pending = nil
        }
      } message: {
        Text(
          "This deletes the branch from \(pending?.target.remoteName ?? "the remote") and may affect other collaborators."
        )
      }
      .alert(
        "Final confirmation: delete remote branch?",
        isPresented: Binding(
          get: { finalConfirmation != nil },
          set: { if !$0 { finalConfirmation = nil } }
        )
      ) {
        Button("Delete Remote Branch", role: .destructive) {
          if let finalConfirmation {
            delete(
              finalConfirmation.target.remoteName,
              finalConfirmation.target.branchName,
              finalConfirmation.reference.targetOID
            )
          }
          finalConfirmation = nil
        }
        Button("Cancel", role: .cancel) {
          finalConfirmation = nil
        }
      } message: {
        Text(
          "GitCurrent uses force-with-lease and refuses deletion if the remote branch changed after the last fetch."
        )
      }
  }
}

struct PartialDiscardDialogModifier: ViewModifier {
  @Binding var request: PartialDiscardRequest?
  let discardHunk: (DiffDocument, DiffHunk) -> Void
  let discardLine: (DiffDocument, DiffHunk, Int) -> Void

  func body(content: Content) -> some View {
    content.confirmationDialog(
      request?.lineIndex == nil ? "Discard selected hunk?" : "Discard selected line?",
      isPresented: Binding(
        get: { request != nil },
        set: { if !$0 { request = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button(
        request?.lineIndex == nil ? "Discard Hunk" : "Discard Line",
        role: .destructive
      ) {
        if let request {
          if let lineIndex = request.lineIndex {
            discardLine(request.document, request.hunk, lineIndex)
          } else {
            discardHunk(request.document, request.hunk)
          }
        }
        request = nil
      }
      Button("Cancel", role: .cancel) {
        request = nil
      }
    } message: {
      Text(
        "GitCurrent stores the original file blob behind a hidden recovery reference. Undo restores it only if the file still matches the post-discard state."
      )
    }
  }
}

struct MergeStartDialogModifier: ViewModifier {
  @Binding var request: PendingMergeRequest?
  let merge: (String) -> Void
  let squashMerge: (String) -> Void

  func body(content: Content) -> some View {
    content.confirmationDialog(
      request?.squash == true ? "Squash merge branch?" : "Merge branch?",
      isPresented: Binding(
        get: { request != nil },
        set: { if !$0 { request = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button(
        request?.squash == true ? "Squash Merge" : "Merge",
        role: .destructive
      ) {
        if let request {
          request.squash ? squashMerge(request.branch) : merge(request.branch)
        }
        request = nil
      }
      Button("Cancel", role: .cancel) {
        request = nil
      }
    } message: {
      Text(
        "GitCurrent resolves the target before execution and preserves the current HEAD in a hidden recovery reference. Without auto-stash, the operation requires a clean working copy."
      )
    }
  }
}
