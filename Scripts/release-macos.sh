#!/bin/sh
set -eu

# One-command macOS release flow:
#   Scripts/release-macos.sh test
#   Scripts/release-macos.sh prod
#
# The script increments the current release line, updates the Xcode build
# settings, builds and signs the app, creates ZIP/DMG installers, optionally
# notarizes both installers, then commits, pushes and creates a GitHub release.

# shellcheck disable=SC1007
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project_file="$project_dir/Current.xcodeproj/project.pbxproj"
scheme=${CURRENT_SCHEME:-Current}
configuration=${CURRENT_CONFIGURATION:-Release}
development_team=${DEVELOPMENT_TEAM:-7QSPARVZYS}
requested_signing_identity=${CODE_SIGN_IDENTITY:-Developer ID Application}
release_remote=${RELEASE_REMOTE:-origin}
release_branch=${RELEASE_BRANCH:-main}
output_root=${CURRENT_PACKAGE_OUTPUT:-"$project_dir/.build/Packages"}
derived_data=${CURRENT_DERIVED_DATA:-"$project_dir/.build/XcodeDerivedData"}
source_packages=${CURRENT_SOURCE_PACKAGES:-"$project_dir/.build/SourcePackages"}
notary_profile=${NOTARYTOOL_PROFILE:-current-notary}
notarize=1
dry_run=0
validate_only=0
release_mode=
signing_identity=
version_updated=0
notes_created=0
committed=0
notes_path=

usage() {
  cat <<'EOF'
Usage:
  Scripts/release-macos.sh test [options]
  Scripts/release-macos.sh prod [options]

Modes:
  test       Increment vX.Y.Z-test.N and the app build number; create a prerelease.
  prod       Use vX.Y.Z when it has not shipped; otherwise increment the patch
             version to vX.Y.(Z+1); create a stable release.

Options:
  --dry-run       Show the next version/tag without changing files or publishing.
  --validate-only Build and verify the next package, then roll back version files.
  --no-notarize   Create a signed but non-notarized package (test-only recommended).
  --help          Show this help.

Environment overrides:
  CODE_SIGN_IDENTITY       Developer ID identity or SHA-1 fingerprint.
  DEVELOPMENT_TEAM         Apple Team ID (default: 7QSPARVZYS).
  NOTARYTOOL_PROFILE       notarytool keychain profile (default: current-notary).
  RELEASE_REMOTE           Git remote (default: origin).
  RELEASE_BRANCH           Release branch (default: main).
  CURRENT_PACKAGE_OUTPUT   Installer output directory (default: .build/Packages).
EOF
}

rollback_generated_version() {
  exit_status=$?
  if [ "$committed" -eq 0 ] && { [ "$exit_status" -ne 0 ] || [ "$validate_only" -eq 1 ]; }; then
    if [ "$version_updated" -eq 1 ]; then
      git -C "$project_dir" restore -- Current.xcodeproj/project.pbxproj >/dev/null 2>&1 || true
    fi
    if [ "$notes_created" -eq 1 ] && [ -n "$notes_path" ]; then
      rm -f "$notes_path"
    fi
  fi
  exit "$exit_status"
}
trap rollback_generated_version EXIT

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 64
fi

release_mode=$1
shift
case "$release_mode" in
  test|prod) ;;
  --help|-h) usage; exit 0 ;;
  *) echo "error: mode must be test or prod: $release_mode" >&2; usage >&2; exit 64 ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      dry_run=1
      ;;
    --validate-only)
      validate_only=1
      ;;
    --no-notarize)
      notarize=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
  shift
done

if [ "$configuration" != "Release" ]; then
  echo "error: release publishing requires CURRENT_CONFIGURATION=Release." >&2
  exit 64
fi

if [ "$release_mode" = "prod" ] && [ "$notarize" -eq 0 ]; then
  echo "error: prod releases must be notarized; remove --no-notarize." >&2
  exit 64
fi

current_branch=$(git -C "$project_dir" branch --show-current)
if [ "$current_branch" != "$release_branch" ]; then
  echo "error: release must run on $release_branch (current: $current_branch)." >&2
  exit 1
fi

if [ -n "$(git -C "$project_dir" status --porcelain)" ]; then
  echo "error: working tree is not clean; commit or stash changes before releasing." >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "error: GitHub CLI is not authenticated; run gh auth login first." >&2
  exit 1
fi

git -C "$project_dir" fetch --tags "$release_remote"

marketing_version=$(awk '/MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+;/ { gsub(";", "", $3); print $3; exit }' "$project_file")
current_build=$(awk '/CURRENT_PROJECT_VERSION = [0-9]+;/ { gsub(";", "", $3); print $3; exit }' "$project_file")

case "$marketing_version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "error: unsupported MARKETING_VERSION: $marketing_version" >&2; exit 1 ;;
esac
case "$current_build" in
  ''|*[!0-9]*) echo "error: unsupported CURRENT_PROJECT_VERSION: $current_build" >&2; exit 1 ;;
esac

next_marketing_version=$marketing_version
if [ "$release_mode" = "test" ]; then
  max_test=0
  for existing_tag in $(git -C "$project_dir" tag --list "v${marketing_version}-test.*"); do
    counter=$(printf '%s\n' "$existing_tag" | sed "s/^v${marketing_version}-test\.//")
    case "$counter" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ "$counter" -gt "$max_test" ]; then
      max_test=$counter
    fi
  done
  next_test=$((max_test + 1))
  release_tag="v${marketing_version}-test.${next_test}"
else
  if git -C "$project_dir" tag --list "v${marketing_version}" | grep -Fqx "v${marketing_version}"; then
    major=$(printf '%s' "$marketing_version" | cut -d. -f1)
    minor=$(printf '%s' "$marketing_version" | cut -d. -f2)
    patch=$(printf '%s' "$marketing_version" | cut -d. -f3)
    next_marketing_version="${major}.${minor}.$((patch + 1))"
  fi
  release_tag="v${next_marketing_version}"
fi

next_build=$((current_build + 1))
if git -C "$project_dir" tag --list "$release_tag" | grep -Fqx "$release_tag"; then
  echo "error: tag already exists locally: $release_tag" >&2
  exit 1
fi
if git -C "$project_dir" ls-remote --exit-code --tags "$release_remote" "refs/tags/$release_tag" >/dev/null 2>&1; then
  echo "error: tag already exists on $release_remote: $release_tag" >&2
  exit 1
fi
if gh release view "$release_tag" >/dev/null 2>&1; then
  echo "error: GitHub Release already exists: $release_tag" >&2
  exit 1
fi

echo "Release mode: $release_mode"
echo "Current app version: $marketing_version ($current_build)"
echo "Next app version:    $next_marketing_version ($next_build)"
echo "Release tag:         $release_tag"
echo "Notarization:        $([ "$notarize" -eq 1 ] && echo enabled || echo disabled)"

if [ "$dry_run" -eq 1 ]; then
  exit 0
fi

if [ "$next_marketing_version" != "$marketing_version" ]; then
  sed -i '' "s/MARKETING_VERSION = ${marketing_version};/MARKETING_VERSION = ${next_marketing_version};/g" "$project_file"
fi
sed -i '' "s/CURRENT_PROJECT_VERSION = ${current_build};/CURRENT_PROJECT_VERSION = ${next_build};/g" "$project_file"
version_updated=1

notes_path="$project_dir/docs/releases/${release_tag}.md"
if [ -e "$notes_path" ]; then
  echo "error: release notes already exist: $notes_path" >&2
  exit 1
fi
mkdir -p "$(dirname "$notes_path")"
{
  printf '# GitCurrent %s\n\n' "$release_tag"
  printf '这是 GitCurrent 的自动发布版本，发布类型为 **%s**。\n\n' "$release_mode"
  printf '%s\n' "## 版本" "" "- 应用版本：\`$next_marketing_version ($next_build)\`" "- Bundle ID：\`com.fun2ex.Current\`" "- 架构：arm64" "- 最低系统：macOS 14 Sonoma" ""
  printf '%s\n' "## 发布内容" "" "- Developer ID Application 签名" "- Hardened Runtime" "- ZIP 安装包" "- 拖拽安装 DMG（包含 \`/Applications\` 快捷方式）" "- SHA-256 校验文件"
  if [ "$notarize" -eq 1 ]; then
    printf '%s\n' '- ZIP 与 DMG 均通过 Apple Notarization。'
  else
    printf '%s\n' '- 本次仅签名，未执行 Apple Notarization。'
  fi
  printf '%s\n' "" "本说明由 \`Scripts/release-macos.sh\` 自动生成。"
} > "$notes_path"
notes_created=1

if [ "$development_team" != "7QSPARVZYS" ]; then
  echo "warning: DEVELOPMENT_TEAM is $development_team; project is configured for 7QSPARVZYS." >&2
fi

bundle_dir="$project_dir/.build/GitBundle/Git"
if [ ! -x "$bundle_dir/bin/git" ]; then
  "$project_dir/Scripts/build-git-bundle.sh"
fi
"$project_dir/Scripts/verify-git-bundle.sh" "$bundle_dir" >/dev/null

identity_listing=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)
if printf '%s' "$requested_signing_identity" | grep -Eq '^[0-9A-Fa-f]{40}$'; then
  identity_line=$(printf '%s\n' "$identity_listing" | awk -v fingerprint="$requested_signing_identity" '$2 == fingerprint { print; exit }')
else
  identity_line=$(printf '%s\n' "$identity_listing" \
    | awk -v identity="$requested_signing_identity" -v team="$development_team" \
      'index($0, identity) && index($0, "(" team ")") { last = $0 } END { if (last) print last }')
fi
if [ -z "$identity_line" ]; then
  echo "error: no valid code-signing identity matches '$requested_signing_identity'." >&2
  exit 2
fi
signing_identity=$(printf '%s\n' "$identity_line" | awk '{ print $2 }')
echo "Using signing identity fingerprint: $signing_identity"

mkdir -p "$output_root" "$derived_data" "$source_packages"
archive_path="$output_root/GitCurrent.xcarchive"
export_path="$output_root/export"
rm -rf "$archive_path" "$export_path"

# Archive unsigned and sign once during export to avoid Xcode 26 duplicate
# signature timestamp failures in Swift Package resource bundles.
/usr/bin/xcodebuild archive \
  -project "$project_file" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$derived_data" \
  -clonedSourcePackagesDirPath "$source_packages" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$development_team" \
  ENABLE_HARDENED_RUNTIME=YES \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=14.0

/usr/bin/xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$project_dir/Config/ExportOptions-DeveloperID.plist" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_IDENTITY="$signing_identity" \
  DEVELOPMENT_TEAM="$development_team"

app_path="$export_path/GitCurrent.app"
[ -d "$app_path" ] || { echo "error: exported app is missing: $app_path" >&2; exit 1; }

sign_macho_files() {
  root=$1
  # shellcheck disable=SC2016
  find "$root" -type f \( -perm +111 -o -name '*.dylib' \) \
    -exec /bin/sh -c '
      signing_identity=$1
      shift
      for candidate do
        if /usr/bin/file "$candidate" | grep -q "Mach-O"; then
          /usr/bin/codesign --force --options runtime --timestamp --sign "$signing_identity" "$candidate"
        fi
      done
    ' sign-macho-files "$signing_identity" {} +
}

sign_macho_files "$app_path/Contents/Resources/Git"
/usr/bin/codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_path"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
signing_dump=$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1 || true)
echo "$signing_dump" | grep -F "TeamIdentifier=$development_team" >/dev/null || { echo "error: Team ID mismatch" >&2; exit 1; }
echo "$signing_dump" | grep -F "Authority=Developer ID Application" >/dev/null || { echo "error: Developer ID signature missing" >&2; exit 1; }

zip_path="$output_root/GitCurrent-${next_marketing_version}-${next_build}-macOS-arm64.zip"
dmg_path="$output_root/GitCurrent-${next_marketing_version}-${next_build}-macOS-arm64.dmg"
dmg_staging="$output_root/.GitCurrent-dmg-root"
rm -f "$zip_path" "$zip_path.sha256" "$dmg_path" "$dmg_path.sha256"

create_dmg() {
  rm -rf "$dmg_staging"
  mkdir -p "$dmg_staging"
  /usr/bin/ditto "$app_path" "$dmg_staging/GitCurrent.app"
  ln -s /Applications "$dmg_staging/Applications"
  /usr/bin/hdiutil create -volname "GitCurrent" -srcfolder "$dmg_staging" \
    -format UDZO -imagekey zlib-level=9 -ov "$dmg_path"
  rm -rf "$dmg_staging"
}

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
create_dmg

if [ "$notarize" -eq 1 ]; then
  /usr/bin/xcrun notarytool submit "$zip_path" --keychain-profile "$notary_profile" --wait
  /usr/bin/xcrun stapler staple "$app_path"
  /usr/bin/xcrun stapler validate "$app_path"
  rm -f "$zip_path"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
  create_dmg
  /usr/bin/xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
  /usr/bin/xcrun stapler staple "$dmg_path"
  /usr/bin/xcrun stapler validate "$dmg_path"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
else
  echo "warning: ZIP and DMG are signed but not notarized." >&2
fi

/usr/bin/shasum -a 256 "$zip_path" > "$zip_path.sha256"
/usr/bin/shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
/usr/bin/shasum -a 256 "$zip_path" "$dmg_path"

git -C "$project_dir" diff --check

if [ "$validate_only" -eq 1 ]; then
  echo "Validation complete; no commit, tag, push or GitHub Release was created."
  exit 0
fi

git -C "$project_dir" add "$project_file" "$notes_path"
git -C "$project_dir" commit -m "chore: prepare $release_tag release"
committed=1
git -C "$project_dir" tag -a "$release_tag" -m "GitCurrent $release_tag"
git -C "$project_dir" push "$release_remote" "$release_branch"
git -C "$project_dir" push "$release_remote" "$release_tag"

release_args=
if [ "$release_mode" = "test" ]; then
  release_args="--prerelease"
else
  release_args="--latest"
fi
gh release create "$release_tag" \
  "$zip_path" "$dmg_path" "$zip_path.sha256" "$dmg_path.sha256" \
  --verify-tag \
  --title "GitCurrent $release_tag" \
  --notes-file "$notes_path" \
  $release_args

echo "Release published: $release_tag"
echo "ZIP: $zip_path"
echo "DMG: $dmg_path"
