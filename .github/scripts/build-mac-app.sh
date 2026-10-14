#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
version="$(sed -n 's/.*current = "\([0-9][0-9.]*\)".*/\1/p' AImana/Relay/Sources/RelayKit/RelayVersion.swift)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
if [[ "${GITHUB_EVENT_NAME:-}" == push ]]; then
  [[ "$version" == "${GITHUB_REF_NAME#v}" ]]
fi

xcodegen generate --spec AImana/project.yml
derived="${AIMANA_DERIVED_DATA:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/aimana-mac-derived}"
xcodebuild -project AImana/AImana.xcodeproj -scheme AImanaMac -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO build
app="$derived/Build/Products/Release/AImana.app"
[[ -d "$app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" == com.henrrygarcia.aimana.mac ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
codesign --force --deep -s - "$app"
codesign --verify --deep --strict --verbose=2 "$app"

mkdir -p dist
stage="$(mktemp -d "${TMPDIR:-/tmp}/aimana-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/AImana.app"
ln -s /Applications "$stage/Applications"
hdiutil create -ov -srcfolder "$stage" -volname 'AI·mana' -format UDZO "dist/AImana-$version.dmg"
cp "dist/AImana-$version.dmg" dist/AImana.dmg
