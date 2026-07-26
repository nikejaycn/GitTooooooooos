#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_root=${CURRENT_GIT_BUILD_ROOT:-"$project_dir/.build/GitBundle"}
download_dir="$build_root/downloads"
source_dir="$build_root/sources"
install_root="$build_root/install"
bundle_dir="$build_root/Git"

git_version=2.55.0
git_sha256=457fdb04dc8728e007d4688695e6912e6f680727920f2a40bf11eacc17505357
git_archive="git-$git_version.tar.xz"
git_url="https://www.kernel.org/pub/software/scm/git/$git_archive"

lfs_version=3.7.1
lfs_sha256=76260fb34f4ee622ff0a66b857e5954aa49c7e343a92e57a1ec4a760618c94b2
lfs_archive="git-lfs-darwin-arm64-v$lfs_version.zip"
lfs_url="https://github.com/git-lfs/git-lfs/releases/download/v$lfs_version/$lfs_archive"
lfs_source_archive="git-lfs-v$lfs_version.tar.gz"
lfs_source_sha256=8f56058622edfea1d111e50e9844ef2f5ce670b2dbe4d55d48e765c943af4351
lfs_source_url="https://github.com/git-lfs/git-lfs/releases/download/v$lfs_version/$lfs_source_archive"

mkdir -p "$download_dir" "$source_dir" "$install_root"

download() {
  source_url=$1
  destination=$2
  if [ ! -f "$destination" ]; then
    curl --fail --location --show-error "$source_url" --output "$destination"
  fi
}

verify_sha256() {
  expected=$1
  file=$2
  actual=$(shasum -a 256 "$file")
  actual=${actual%% *}
  if [ "$actual" != "$expected" ]; then
    echo "error: SHA-256 mismatch for $file" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

download "$git_url" "$download_dir/$git_archive"
download "$lfs_url" "$download_dir/$lfs_archive"
download "$lfs_source_url" "$download_dir/$lfs_source_archive"
verify_sha256 "$git_sha256" "$download_dir/$git_archive"
verify_sha256 "$lfs_sha256" "$download_dir/$lfs_archive"
verify_sha256 "$lfs_source_sha256" "$download_dir/$lfs_source_archive"

rm -rf "$source_dir/git-$git_version" "$source_dir/git-lfs-$lfs_version"
tar -xJf "$download_dir/$git_archive" -C "$source_dir"
mkdir -p "$source_dir/git-lfs-$lfs_version"
ditto -x -k "$download_dir/$lfs_archive" "$source_dir/git-lfs-$lfs_version"
tar -xzf "$download_dir/$lfs_source_archive" -C "$source_dir"

rm -rf "$install_root" "$bundle_dir"
mkdir -p "$install_root"

jobs=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
make -C "$source_dir/git-$git_version" -j"$jobs" \
  prefix=/ \
  RUNTIME_PREFIX=YesPlease \
  NO_GETTEXT=YesPlease \
  NO_TCLTK=YesPlease \
  NO_PERL=YesPlease \
  NO_PYTHON=YesPlease \
  NO_RUST=YesPlease \
  NO_INSTALL_HARDLINKS=YesPlease \
  CFLAGS="-O2 -mmacosx-version-min=14.0 -arch arm64" \
  LDFLAGS="-mmacosx-version-min=14.0 -arch arm64" \
  DESTDIR="$install_root" \
  all

make -C "$source_dir/git-$git_version" \
  prefix=/ \
  RUNTIME_PREFIX=YesPlease \
  NO_GETTEXT=YesPlease \
  NO_TCLTK=YesPlease \
  NO_PERL=YesPlease \
  NO_PYTHON=YesPlease \
  NO_RUST=YesPlease \
  NO_INSTALL_HARDLINKS=YesPlease \
  CFLAGS="-O2 -mmacosx-version-min=14.0 -arch arm64" \
  LDFLAGS="-mmacosx-version-min=14.0 -arch arm64" \
  DESTDIR="$install_root" \
  install

make -C "$source_dir/git-$git_version" -j"$jobs" \
  prefix=/ \
  RUNTIME_PREFIX=YesPlease \
  NO_GETTEXT=YesPlease \
  NO_TCLTK=YesPlease \
  NO_PERL=YesPlease \
  NO_PYTHON=YesPlease \
  NO_RUST=YesPlease \
  NO_INSTALL_HARDLINKS=YesPlease \
  CFLAGS="-O2 -mmacosx-version-min=14.0 -arch arm64" \
  LDFLAGS="-mmacosx-version-min=14.0 -arch arm64" \
  contrib/credential/osxkeychain/git-credential-osxkeychain

mkdir -p "$bundle_dir"
mv "$install_root/bin" "$bundle_dir/bin"
if [ -d "$install_root/libexec" ]; then
  mv "$install_root/libexec" "$bundle_dir/libexec"
fi
if [ -d "$install_root/share" ]; then
  mv "$install_root/share" "$bundle_dir/share"
fi
cp "$source_dir/git-$git_version/contrib/credential/osxkeychain/git-credential-osxkeychain" \
  "$bundle_dir/libexec/git-core/git-credential-osxkeychain"

lfs_binary=$(find "$source_dir/git-lfs-$lfs_version" -type f -name git-lfs -perm +111 | head -1)
if [ -z "$lfs_binary" ]; then
  echo "error: Git LFS archive did not contain an executable git-lfs" >&2
  exit 1
fi
cp "$lfs_binary" "$bundle_dir/bin/git-lfs"

licenses_dir="$bundle_dir/share/current/licenses"
mkdir -p "$licenses_dir"
cp "$source_dir/git-$git_version/COPYING" "$licenses_dir/Git-GPL-2.0.txt"
lfs_license=$(find "$source_dir/git-lfs-$lfs_version" -type f -name LICENSE.md | head -1)
if [ -n "$lfs_license" ]; then
  cp "$lfs_license" "$licenses_dir/Git-LFS-MIT.txt"
fi
cp "$project_dir/Resources/GitBundle.lock.json" "$bundle_dir/share/current/GitBundle.lock.json"
cp "$project_dir/Resources/GitBundle.sbom.cdx.json" \
  "$bundle_dir/share/current/GitBundle.sbom.cdx.json"
cp "$project_dir/Resources/ThirdPartyNotices.md" \
  "$bundle_dir/share/current/ThirdPartyNotices.md"
cp "$project_dir/Resources/GitBundle.gitconfig" \
  "$bundle_dir/share/current/gitconfig"

"$project_dir/Scripts/verify-git-bundle.sh" "$bundle_dir"
echo "Git bundle ready at $bundle_dir"
