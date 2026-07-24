# ADR-018: Native Git LFS management

- Status: Accepted
- Date: 2026-07-24
- Feature: ADV-03 / WP-048

## Context

Current bundles Git LFS 3.7.1, but a version label alone does not provide a usable repository
workflow. Version 1.0 needs capability detection, tracking-rule management, fetch/pull, and safe
local pruning while remaining compatible with a custom Git executable that may not expose Git
LFS.

`git lfs track` normally installs hooks even when it only lists rules. Repository refreshes are
read operations and must not mutate `.git/hooks`. Tracking an existing Git blob also does not
rewrite that blob or historical commits into LFS automatically.

## Decision

- `GitEngineProtocol` exposes repository LFS state and typed LFS mutations. UI code never launches
  Git or Git LFS directly.
- A failed `git lfs version` is represented as an unavailable optional capability; it does not
  prevent a repository snapshot from loading.
- Rules are read with `git lfs track --json` and
  `GIT_LFS_TRACK_NO_INSTALL_HOOKS=1`. The bounded JSON parser validates pattern count, field size,
  required fields, and NUL safety.
- Root `.gitattributes` rules can be removed in the UI. Nested, global, system, and excluded rules
  remain visible but read-only because `git lfs untrack` only edits the root attributes file.
- Track first runs `git lfs install --local`, then invokes the option-safe track command. This
  makes the bundled toolchain work on machines without a prior global Git LFS installation.
- Fetch, recent fetch, and pull use the current repository's configured remote semantics.
- Prune always uses `--verify-remote`, requires explicit confirmation, and runs through the
  repository mutation queue.
- Track and untrack update `.gitattributes` only. Current explicitly tells the user that existing
  Git blobs and history are not migrated. History-rewriting `git lfs migrate --everything` is not
  exposed as a routine version 1.0 action.

## Consequences

Repository snapshots perform bounded LFS capability reads alongside other repository data. A
custom or older LFS executable that cannot emit machine-readable rules remains usable for transfer
commands, but the UI shows that rule inspection is unavailable.

Track may fail when an existing custom pre-push hook prevents Git LFS from installing its hook.
Current preserves that failure rather than overwriting user hook content.

## Verification

- Parser tests cover tracked, excluded, lockable, nested-source, malformed, and unsafe JSON.
- Command tests cover unavailable capability handling, no-hook read environment, option-safe
  track/untrack, local installation, fetch/recent, pull, verified prune, and invalid patterns.
- A real Git LFS 3.7.1 fixture verifies read-side hook purity, automatic local initialization,
  lockable tracking, machine-readable listing, and untracking.
- RepositoryActor tests prove LFS mutations share the serialized mutation queue and refresh the
  authoritative snapshot.
- Native macOS UI QA verifies Ready/version state, lockable rules, repository action menus,
  untrack context action, and the Track dialog's non-migration warning.
