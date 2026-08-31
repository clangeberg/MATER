#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_binary="${TMPDIR:-/tmp}/mater-core-tests"
state_test_binary="${TMPDIR:-/tmp}/mater-editor-state-tests"
export_test_binary="${TMPDIR:-/tmp}/mater-export-tests"
document_test_binary="${TMPDIR:-/tmp}/mater-document-tests"
module_cache="${TMPDIR:-/tmp}/mater-core-module-cache"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
compatibility_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
if [[ -d "$compatibility_sdk" ]]; then
  sdk_path="$compatibility_sdk"
fi

swiftc \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "$project_dir/Sources/MATER/StockholmModel.swift" \
  "$project_dir/Sources/MATER/StructureModel.swift" \
  "$project_dir/Sources/MATER/CurationAnalysis.swift" \
  "$project_dir/Sources/MATER/AlignmentNavigation.swift" \
  "$project_dir/Tests/CoreTestMain.swift" \
  -o "$test_binary"

"$test_binary" "$@"

swiftc \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "$project_dir/Sources/MATER/StockholmModel.swift" \
  "$project_dir/Sources/MATER/StructureModel.swift" \
  "$project_dir/Sources/MATER/CurationAnalysis.swift" \
  "$project_dir/Sources/MATER/EditorState.swift" \
  "$project_dir/Tests/EditorStateRegressionMain.swift" \
  -o "$state_test_binary"

"$state_test_binary"

swiftc \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "$project_dir/Sources/MATER/StockholmModel.swift" \
  "$project_dir/Sources/MATER/StructureModel.swift" \
  "$project_dir/Sources/MATER/EditorState.swift" \
  "$project_dir/Sources/MATER/AlignmentPalette.swift" \
  "$project_dir/Sources/MATER/AlignmentExporter.swift" \
  "$project_dir/Tests/ExportRegressionMain.swift" \
  -framework AppKit \
  -framework PDFKit \
  -o "$export_test_binary"

"$export_test_binary"

swiftc \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "$project_dir/Sources/MATER/StockholmModel.swift" \
  "$project_dir/Sources/MATER/StructureModel.swift" \
  "$project_dir/Sources/MATER/CurationAnalysis.swift" \
  "$project_dir/Sources/MATER/EditorState.swift" \
  "$project_dir/Sources/MATER/StockholmDocument.swift" \
  "$project_dir/Sources/MATER/AlignmentShiftController.swift" \
  "$project_dir/Tests/DocumentRegressionMain.swift" \
  -framework AppKit \
  -framework SwiftUI \
  -framework CryptoKit \
  -o "$document_test_binary"

MATER_RECOVERY_DIRECTORY="${TMPDIR:-/tmp}/mater-recovery-tests" "$document_test_binary"
