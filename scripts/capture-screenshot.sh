#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
binary="${TMPDIR:-/tmp}/mater-screenshot"
module_cache="${TMPDIR:-/tmp}/mater-screenshot-module-cache"
sdk_path="${MATER_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
sources=()
while IFS= read -r source; do
  if [[ "$(basename "$source")" != "MATERApp.swift" ]]; then sources+=("$source"); fi
done < <(find "$project_dir/Sources/MATER" -name '*.swift' -type f | sort)

swiftc -O \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "${sources[@]}" \
  "$project_dir/Tests/ScreenshotMain.swift" \
  -framework AppKit \
  -framework SwiftUI \
  -framework PDFKit \
  -framework CryptoKit \
  -o "$binary"

mkdir -p "$project_dir/docs/images"
"$binary" \
  "$project_dir/Examples/Rfam/RF01763-Guanidine-III.sto" \
  "$project_dir/docs/images/mater-hero-quality-inspector.png"

echo "$project_dir/docs/images/mater-hero-quality-inspector.png"
