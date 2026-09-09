#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
archive="MATER-${version}-macOS-universal.zip"

./scripts/build-app.sh
mkdir -p dist
rm -f "dist/$archive" "dist/$archive.sha256"
ditto -c -k --sequesterRsrc --keepParent dist/MATER.app "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")

echo "$project_dir/dist/$archive"
echo "$project_dir/dist/$archive.sha256"
