#!/usr/bin/env bash
#
# Builds a signed and notarized Gravitune disk image.
#
# Usage: scripts/release.sh 1.0.0
#
# Requirements:
#   - A "Developer ID Application" certificate in the keychain.
#   - A notarytool keychain profile. Its name defaults to "notary"; override it with NOTARY_PROFILE.
#
# The team comes from the project. Override it with TEAM_ID to sign with your own account.

set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: scripts/release.sh <major.minor.patch>" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
    echo "The working tree has uncommitted changes." >&2
    exit 1
fi

scheme="gravitune"
app_name="Gravitune.app"
identity="Developer ID Application"
notary_profile="${NOTARY_PROFILE:-notary}"
team_id="${TEAM_ID:-$(grep -m1 'DEVELOPMENT_TEAM = ' gravitune.xcodeproj/project.pbxproj | sed -E 's/.*= (.*);/\1/')}"

# Work outside the project: iCloud adds extended attributes that invalidate the app's strict
# code signature when the project lives in a synced folder such as Documents.
work_dir="$(mktemp -d)"
archive="$work_dir/$scheme.xcarchive"
export_dir="$work_dir/export"
stage_dir="$work_dir/stage"
dmg_name="Gravitune-$version.dmg"
dmg="$work_dir/$dmg_name"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Leftover copies of the app would stay registered in Launch Services, which can confuse the Dock.
cleanup() {
    find "$work_dir" -type d -name "$app_name" -prune -exec "$lsregister" -u {} \; 2>/dev/null || true
    rm -rf "$work_dir"
}
trap cleanup EXIT

echo "==> Archiving version $version"
xcodebuild archive \
    -project gravitune.xcodeproj \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive" \
    MARKETING_VERSION="$version" \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$identity" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    -quiet

echo "==> Exporting for Developer ID"
cat > "$work_dir/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$identity</string>
    <key>teamID</key>
    <string>$team_id</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$work_dir/ExportOptions.plist" \
    -quiet

echo "==> Verifying the signature"
codesign --verify --deep --strict "$export_dir/$app_name"

echo "==> Creating the disk image"
mkdir -p "$stage_dir"
cp -R "$export_dir/$app_name" "$stage_dir/"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -quiet -volname "Gravitune" -srcfolder "$stage_dir" -format UDZO -ov "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"

echo "==> Notarizing"
xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait

echo "==> Stapling"
xcrun stapler staple -q "$dmg"
xcrun stapler validate -q "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"

mkdir -p build
mv -f "$dmg" "build/$dmg_name"

echo "==> Done: build/$dmg_name"
shasum -a 256 "build/$dmg_name"
