#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/Git" >&2
  exit 64
fi

bundle_dir=$(CDPATH= cd -- "$1" && pwd)
git="$bundle_dir/bin/git"
lfs="$bundle_dir/bin/git-lfs"

if [ ! -x "$git" ] || [ ! -x "$lfs" ]; then
  echo "error: bundle must contain executable bin/git and bin/git-lfs" >&2
  exit 1
fi

case $(file "$git") in
  *arm64*) ;;
  *)
    echo "error: bundled Git is not arm64" >&2
    exit 1
    ;;
esac

if otool -L "$git" | grep -E '/opt/homebrew|/usr/local' >/dev/null; then
  echo "error: bundled Git links to a package-manager path" >&2
  otool -L "$git" >&2
  exit 1
fi

git_version=$("$git" --version)
lfs_version=$(PATH="$bundle_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$lfs" version)
case "$git_version" in
  "git version 2.55.0") ;;
  *)
    echo "error: unexpected Git version: $git_version" >&2
    exit 1
    ;;
esac
case "$lfs_version" in
  "git-lfs/3.7.1 "*) ;;
  *)
    echo "error: unexpected Git LFS version: $lfs_version" >&2
    exit 1
    ;;
esac

smoke_root=$(mktemp -d "${TMPDIR:-/tmp}/current-git-smoke.XXXXXX")
trap 'rm -rf "$smoke_root"' EXIT HUP INT TERM
PATH="$bundle_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$git" -c init.defaultBranch=main init "$smoke_root/repository" >/dev/null
PATH="$bundle_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$git" -C "$smoke_root/repository" lfs version >/dev/null
PATH="$bundle_dir/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$git" -C "$smoke_root/repository" status --porcelain=v2 >/dev/null

echo "$git_version"
echo "$lfs_version"
echo "Bundle verification passed."
