#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_binary="${TMPDIR:-/tmp}/mater-gui-stress-tests"
module_cache="${TMPDIR:-/tmp}/mater-gui-stress-module-cache"
sdk_path="${MATER_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
sources=()
while IFS= read -r source; do
  if [[ "$(basename "$source")" != "MATERApp.swift" ]]; then sources+=("$source"); fi
done < <(find "$project_dir/Sources/MATER" -name '*.swift' -type f | sort)

swiftc -O \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "${sources[@]}" \
  "$project_dir/Tests/GUIStressMain.swift" \
  -framework AppKit \
  -framework SwiftUI \
  -framework PDFKit \
  -framework CryptoKit \
  -o "$test_binary"

if [[ "${1:-}" == "--quick" ]]; then
  MATER_STRESS_QUICK=1 "$test_binary"
else
  "$test_binary"
fi
