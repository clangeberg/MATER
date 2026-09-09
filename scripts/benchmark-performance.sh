#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
benchmark_binary="${TMPDIR:-/tmp}/mater-performance-benchmark"
module_cache="${TMPDIR:-/tmp}/mater-benchmark-module-cache"
sdk_path="${MATER_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"

swiftc -O \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "$project_dir/Sources/MATER/StockholmModel.swift" \
  "$project_dir/Sources/MATER/StructureModel.swift" \
  "$project_dir/Sources/MATER/CurationAnalysis.swift" \
  "$project_dir/Tests/PerformanceBenchmarkMain.swift" \
  -o "$benchmark_binary"

"$benchmark_binary" "${1:-5000}" "${2:-1000}"
