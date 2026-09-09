#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"

sdk_path="${MATER_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
module_cache="$project_dir/.build/ModuleCache"
export SDKROOT="$sdk_path"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFT_MODULE_CACHE_PATH="$module_cache"

swift build -c release --arch arm64 --build-path .build-arm64 --disable-sandbox --sdk "$sdk_path"
swift build -c release --arch x86_64 --build-path .build-x86_64 --disable-sandbox --sdk "$sdk_path"

app_dir="$project_dir/dist/MATER.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
lipo -create \
  "$project_dir/.build-arm64/release/MATER" \
  "$project_dir/.build-x86_64/release/MATER" \
  -output "$app_dir/Contents/MacOS/MATER"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/Assets/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/docs/MATER-User-Guide.md" "$app_dir/Contents/Resources/MATER-User-Guide.md"
codesign --force --sign - "$app_dir"

echo "$app_dir"
