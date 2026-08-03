#!/bin/sh
set -eu

# Keep the repository's generated build tree bounded without touching source
# files, shared dependency stores, or the Git bundle required by Release builds.
#
# The default is a dry-run. Use --apply only when no build, test, archive, or
# release command is currently running.

project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
build_root="$project_dir/.build"
cache_days=${CURRENT_BUILD_CACHE_DAYS:-3}
keep_releases=${CURRENT_RELEASE_KEEP_COUNT:-3}
apply=0
candidate_count=0
temp_root=
lock_dir="$build_root/.cleanup-build-artifacts.lock"
lock_acquired=0

usage() {
  cat <<'EOF'
Usage:
  Scripts/cleanup-build-artifacts.sh [options]

Options:
  --apply                 Delete the selected stale caches and old artifacts.
  --cache-days DAYS       Keep build caches touched within DAYS (default: 3).
  --keep-releases COUNT   Keep the newest COUNT release groups (default: 3).
  --help                  Show this help.

Environment overrides:
  CURRENT_BUILD_CACHE_DAYS
  CURRENT_RELEASE_KEEP_COUNT

The script always preserves .build/GitBundle and the shared dependency stores:
.build/SourcePackages, .build/checkouts, .build/repositories, and
.build/artifacts. Without --apply it only prints what would be removed.
EOF
}

die() {
  echo "error: $*" >&2
  exit 64
}

is_positive_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$1" -gt 0 ]
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      apply=1
      ;;
    --cache-days)
      [ "$#" -ge 2 ] || die "--cache-days requires a value"
      cache_days=$2
      shift
      ;;
    --keep-releases)
      [ "$#" -ge 2 ] || die "--keep-releases requires a value"
      keep_releases=$2
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

is_positive_integer "$cache_days" || die "cache days must be a positive integer"
is_positive_integer "$keep_releases" || die "release count must be a positive integer"
cache_minutes=$((cache_days * 24 * 60))

if [ ! -d "$build_root" ]; then
  echo "No .build directory; nothing to clean."
  exit 0
fi

# Every deletion target is derived from this exact repository-local path. This
# guard prevents an accidental future change from making the script recursive
# over the repository or another broad directory.
assert_build_child() {
  case "$1" in
    "$build_root"/*) ;;
    *) die "refusing to remove path outside .build: $1" ;;
  esac
}

cleanup_path() {
  cleanup_label=$1
  cleanup_target=$2
  cleanup_verify_stale=${3:-0}
  [ -e "$cleanup_target" ] || [ -L "$cleanup_target" ] || return 0
  assert_build_child "$cleanup_target"

  cleanup_size=$(du -sh "$cleanup_target" 2>/dev/null | awk 'NR == 1 { print $1 }')
  cleanup_size=${cleanup_size:-unknown}
  if [ "$apply" -eq 1 ] && [ "$cleanup_verify_stale" -eq 1 ] \
    && ! is_stale_tree "$cleanup_target"; then
    printf 'Skipped active cache       %s\n' "$cleanup_target"
    return 0
  fi
  candidate_count=$((candidate_count + 1))

  if [ "$apply" -eq 1 ]; then
    rm -rf "$cleanup_target"
    printf 'Removed %-24s %s (%s)\n' "$cleanup_label" "$cleanup_target" "$cleanup_size"
  else
    printf 'Would remove %-20s %s (%s)\n' "$cleanup_label" "$cleanup_target" "$cleanup_size"
  fi
}

has_recent_content() {
  cleanup_target=$1
  find "$cleanup_target" -mmin -"$cache_minutes" -print 2>/dev/null | grep -q .
}

is_stale_tree() {
  ! has_recent_content "$1"
}

cleanup_runtime() {
  if [ -n "$temp_root" ] && [ -d "$temp_root" ]; then
    rm -rf "$temp_root"
  fi
  if [ "$lock_acquired" -eq 1 ] && [ -d "$lock_dir" ]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}

trap cleanup_runtime EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! mkdir "$lock_dir" 2>/dev/null; then
  die "another build cleanup appears to be running: $lock_dir"
fi
lock_acquired=1
temp_root=$(mktemp -d "${TMPDIR:-/tmp}/gitcurrent-build-clean.XXXXXX")

if [ "$apply" -eq 1 ]; then
  echo "Applying build cleanup (cache>${cache_days}d, keep=${keep_releases} release groups)"
else
  echo "Dry-run build cleanup (cache>${cache_days}d, keep=${keep_releases} release groups)"
fi

# Shared dependency stores are deliberately retained even when old. Every
# other top-level directory is generated state and is eligible only when no
# file or directory anywhere in its tree was modified during the retention
# window. This covers current and future custom QA/DerivedData directory names.
for cleanup_target in "$build_root"/*; do
  [ -d "$cleanup_target" ] || continue
  cleanup_name=${cleanup_target##*/}

  case "$cleanup_name" in
    GitBundle|SourcePackages|checkouts|repositories|artifacts|Packages|ReleaseArtifacts|releases)
      continue
      ;;
  esac

  if is_stale_tree "$cleanup_target"; then
    cleanup_path "stale build cache" "$cleanup_target" 1
  fi
done

# Remove old top-level package archives while keeping the newest release groups.
# A ZIP is the group anchor; its matching DMG and checksum files are removed
# together. Current archive/export staging directories are handled separately.
prune_package_archives() {
  cleanup_dir=$1
  cleanup_label=$2
  cleanup_list="$temp_root/package-archives.list"
  : > "$cleanup_list"

  for cleanup_archive in "$cleanup_dir"/*.zip; do
    [ -f "$cleanup_archive" ] || continue
    cleanup_mtime=$(stat -f '%m' "$cleanup_archive" 2>/dev/null || true)
    [ -n "$cleanup_mtime" ] || continue
    printf '%s\t%s\n' "$cleanup_mtime" "$cleanup_archive" >> "$cleanup_list"
  done

  [ -s "$cleanup_list" ] || return 0

  cleanup_old_list="$temp_root/old-package-archives.list"
  LC_ALL=C sort -rn "$cleanup_list" \
    | awk -F '\t' -v keep="$keep_releases" 'NR > keep { print $2 }' \
    > "$cleanup_old_list"
  while IFS= read -r cleanup_archive; do
    [ -n "$cleanup_archive" ] || continue
    cleanup_stem=${cleanup_archive%.zip}
    cleanup_path "$cleanup_label" "$cleanup_archive"
    cleanup_path "$cleanup_label" "$cleanup_stem.dmg"
    cleanup_path "$cleanup_label" "$cleanup_stem.zip.sha256"
    cleanup_path "$cleanup_label" "$cleanup_stem.dmg.sha256"
  done < "$cleanup_old_list"
}

# Keep only the newest direct release entries. Entries are either a release
# directory or a ZIP plus its checksum; the directory/ZIP is the group anchor.
prune_release_entries() {
  cleanup_dir=$1
  cleanup_label=$2
  cleanup_list="$temp_root/$(basename "$cleanup_dir").list"
  : > "$cleanup_list"

  for cleanup_entry in "$cleanup_dir"/*; do
    [ -e "$cleanup_entry" ] || [ -L "$cleanup_entry" ] || continue
    case "$cleanup_entry" in
      *.zip)
        ;;
      *)
        [ -d "$cleanup_entry" ] || continue
        ;;
    esac
    cleanup_mtime=$(stat -f '%m' "$cleanup_entry" 2>/dev/null || true)
    [ -n "$cleanup_mtime" ] || continue
    printf '%s\t%s\n' "$cleanup_mtime" "$cleanup_entry" >> "$cleanup_list"
  done

  [ -s "$cleanup_list" ] || return 0

  cleanup_old_list="$temp_root/old-release-entries.list"
  LC_ALL=C sort -rn "$cleanup_list" \
    | awk -F '\t' -v keep="$keep_releases" 'NR > keep { print $2 }' \
    > "$cleanup_old_list"
  while IFS= read -r cleanup_entry; do
    [ -n "$cleanup_entry" ] || continue
    case "$cleanup_entry" in
      *.zip)
        cleanup_stem=${cleanup_entry%.zip}
        cleanup_path "$cleanup_label" "$cleanup_entry"
        cleanup_path "$cleanup_label" "$cleanup_stem.zip.sha256"
        ;;
      *)
        cleanup_path "$cleanup_label" "$cleanup_entry"
        ;;
    esac
  done < "$cleanup_old_list"
}

packages_dir="$build_root/Packages"
if [ -d "$packages_dir" ]; then
  for cleanup_name in \
    GitCurrent.xcarchive \
    UnsignedFlowTest.xcarchive \
    export \
    UnsignedFlowTestExport \
    .GitCurrent-dmg-root; do
    cleanup_target="$packages_dir/$cleanup_name"
    if { [ -e "$cleanup_target" ] || [ -L "$cleanup_target" ]; } \
      && is_stale_tree "$cleanup_target"; then
      cleanup_path "stale package staging" "$cleanup_target" 1
    fi
  done
  prune_package_archives "$packages_dir" "old package archive"
fi

release_artifacts_dir="$build_root/ReleaseArtifacts"
if [ -d "$release_artifacts_dir" ]; then
  prune_release_entries "$release_artifacts_dir" "old release artifact"
fi

releases_dir="$build_root/releases"
if [ -d "$releases_dir" ]; then
  prune_release_entries "$releases_dir" "old release bundle"
fi

if [ "$candidate_count" -eq 0 ]; then
  echo "Nothing matched the cleanup rule."
elif [ "$apply" -eq 0 ]; then
  echo "Dry-run only: no files changed. Re-run with --apply to remove $candidate_count item(s)."
else
  echo "Removed $candidate_count item(s)."
fi
