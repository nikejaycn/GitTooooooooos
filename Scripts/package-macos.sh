#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scheme=${CURRENT_SCHEME:-Current}
configuration=${CURRENT_CONFIGURATION:-Release}
development_team=${DEVELOPMENT_TEAM:-7QSPARVZYS}
requested_signing_identity=${CODE_SIGN_IDENTITY:-Developer ID Application}
signing_identity=
output_root=${CURRENT_PACKAGE_OUTPUT:-"$project_dir/.build/Packages"}
derived_data=${CURRENT_DERIVED_DATA:-"$project_dir/.build/XcodeDerivedData"}
source_packages=${CURRENT_SOURCE_PACKAGES:-"$project_dir/.build/SourcePackages"}
notarize=${NOTARIZE:-0}
notary_profile=${NOTARYTOOL_PROFILE:-}
skip_git_bundle=${SKIP_GIT_BUNDLE_BUILD:-0}

usage() {
  cat <<'EOF'
Usage: Scripts/package-macos.sh [--notarize|--no-notarize]

Builds the arm64 macOS Release archive, signs it with Developer ID Application,
exports GitCurrent.app, creates ZIP and DMG installers, and writes SHA-256 sidecars.

Environment overrides:
  CODE_SIGN_IDENTITY       Signing identity or SHA-1 fingerprint (default: Developer ID Application)
  DEVELOPMENT_TEAM         Apple team ID (default: 7QSPARVZYS)
  CURRENT_PACKAGE_OUTPUT   Output directory (default: .build/Packages)
  NOTARYTOOL_PROFILE       notarytool keychain profile for --notarize
  SKIP_GIT_BUNDLE_BUILD    Set to 1 only when the locked Git bundle already exists
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --notarize)
      notarize=1
      ;;
    --no-notarize)
      notarize=0
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
  echo "error: signed packaging must use CURRENT_CONFIGURATION=Release" >&2
  exit 64
fi

if [ "$development_team" != "7QSPARVZYS" ]; then
  echo "warning: DEVELOPMENT_TEAM is $development_team; the project is configured for 7QSPARVZYS." >&2
fi

bundle_dir="$project_dir/.build/GitBundle/Git"
if [ ! -x "$bundle_dir/bin/git" ]; then
  if [ "$skip_git_bundle" = "1" ]; then
    echo "error: locked Git bundle is missing and SKIP_GIT_BUNDLE_BUILD=1." >&2
    exit 1
  fi
  "$project_dir/Scripts/build-git-bundle.sh"
fi
"$project_dir/Scripts/verify-git-bundle.sh" "$bundle_dir" >/dev/null

identity_listing=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)
if printf '%s' "$requested_signing_identity" | /usr/bin/grep -Eq '^[0-9A-Fa-f]{40}$'; then
  identity_line=$(printf '%s\n' "$identity_listing" \
    | /usr/bin/awk -v fingerprint="$requested_signing_identity" '$2 == fingerprint { print; exit }')
else
  identity_line=$(printf '%s\n' "$identity_listing" \
    | /usr/bin/awk -v identity="$requested_signing_identity" \
      -v team="$development_team" \
      'index($0, identity) && index($0, "(" team ")") { last = $0 } END { if (last) print last }')
fi
if [ -z "$identity_line" ]; then
  echo "error: no valid code-signing identity matches '$requested_signing_identity'." >&2
  echo "Install the Developer ID Application certificate and its private key in the login keychain, then retry." >&2
  exit 2
fi
signing_identity=$(printf '%s\n' "$identity_line" | /usr/bin/awk '{ print $2 }')
if [ -z "$signing_identity" ]; then
  echo "error: could not resolve a certificate fingerprint for '$requested_signing_identity'." >&2
  exit 2
fi
echo "Using signing identity fingerprint: $signing_identity"

mkdir -p "$output_root" "$derived_data" "$source_packages"
archive_path="$output_root/GitCurrent.xcarchive"
export_path="$output_root/export"
rm -rf "$archive_path" "$export_path"

# Archive unsigned, then sign once during export. This avoids Xcode 26's
# duplicate-signature timestamp failure for Swift package resource bundles.
/usr/bin/xcodebuild archive \
  -project "$project_dir/Current.xcodeproj" \
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
if [ ! -d "$app_path" ]; then
  echo "error: xcodebuild did not export $app_path." >&2
  exit 1
fi

# The Git toolchain is stored under Resources rather than a standard nested-code
# directory. Sign every Mach-O object there before signing the outer app again.
sign_macho_files() {
  root=$1
  /usr/bin/find "$root" -type f \( -perm +111 -o -name '*.dylib' \) \
    -exec /bin/sh -c '
      signing_identity=$1
      shift
      for candidate do
        if /usr/bin/file "$candidate" | /usr/bin/grep -q "Mach-O"; then
          /usr/bin/codesign --force --options runtime --timestamp \
            --sign "$signing_identity" "$candidate"
        fi
      done
    ' sign-macho-files "$signing_identity" {} +
}

sign_macho_files "$app_path/Contents/Resources/Git"
/usr/bin/codesign --force --options runtime --timestamp \
  --sign "$signing_identity" "$app_path"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

signing_dump=$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1 || true)
echo "$signing_dump" | /usr/bin/grep -F "TeamIdentifier=$development_team" >/dev/null || {
  echo "error: exported app is not signed by team $development_team." >&2
  exit 1
}
echo "$signing_dump" | /usr/bin/grep -F "Authority=Developer ID Application" >/dev/null || {
  echo "error: exported app is not signed with a Developer ID Application certificate." >&2
  exit 1
}

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$app_path/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$app_path/Contents/Info.plist")
zip_path="$output_root/GitCurrent-${version}-${build_number}-macOS-arm64.zip"
dmg_path="$output_root/GitCurrent-${version}-${build_number}-macOS-arm64.dmg"
dmg_staging="$output_root/.GitCurrent-dmg-root"
rm -f "$zip_path" "$zip_path.sha256" "$dmg_path" "$dmg_path.sha256"
rm -rf "$dmg_staging"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

create_dmg() {
  rm -rf "$dmg_staging"
  /bin/mkdir -p "$dmg_staging"
  /usr/bin/ditto "$app_path" "$dmg_staging/GitCurrent.app"
  /bin/ln -s /Applications "$dmg_staging/Applications"
  /usr/bin/hdiutil create \
    -volname "GitCurrent" \
    -srcfolder "$dmg_staging" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov "$dmg_path"
  rm -rf "$dmg_staging"
}

create_dmg

if [ "$notarize" = "1" ]; then
  if [ -z "$notary_profile" ]; then
    echo "error: --notarize requires NOTARYTOOL_PROFILE." >&2
    echo "Create it with xcrun notarytool store-credentials using an App Store Connect API key." >&2
    exit 2
  fi
  /usr/bin/xcrun notarytool submit "$zip_path" \
    --keychain-profile "$notary_profile" \
    --wait
  /usr/bin/xcrun stapler staple "$app_path"
  /usr/bin/xcrun stapler validate "$app_path"
  rm -f "$zip_path"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
  # Rebuild the DMG so it contains the stapled app, then notarize the DMG itself.
  create_dmg
  /usr/bin/xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait
  /usr/bin/xcrun stapler staple "$dmg_path"
  /usr/bin/xcrun stapler validate "$dmg_path"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
else
  echo "warning: package is Developer ID signed but ZIP and DMG are not notarized." >&2
fi

/usr/bin/shasum -a 256 "$zip_path" > "$zip_path.sha256"
/usr/bin/shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
echo "Package: $zip_path"
echo "Checksum: $zip_path.sha256"
echo "Package: $dmg_path"
echo "Checksum: $dmg_path.sha256"
