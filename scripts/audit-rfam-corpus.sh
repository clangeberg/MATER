#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cache_dir="${MATER_RFAM_CACHE:-$project_dir/.build/rfam-corpus}"
archive="$cache_dir/Rfam.seed.gz"
decompressed="$cache_dir/Rfam.seed"
test_binary="${TMPDIR:-/tmp}/mater-rfam-corpus-audit"
module_cache="${TMPDIR:-/tmp}/mater-rfam-corpus-module-cache"
sdk_path="${MATER_SDK_PATH:-$(xcrun --sdk macosx --show-sdk-path)}"
sample_count="${1:-250}"
source_url="https://ftp.ebi.ac.uk/pub/databases/Rfam/CURRENT/Rfam.seed.gz"

if [[ ! "$sample_count" =~ ^[0-9]+$ ]] || (( sample_count < 100 || sample_count > 500 )); then
  echo "Sample count must be an integer from 100 through 500." >&2
  exit 2
fi

mkdir -p "$cache_dir"
if [[ ! -s "$archive" ]]; then
  echo "Downloading the current official Rfam SEED corpus…"
  curl --fail --location --retry 3 --output "$archive.part" "$source_url"
  gzip -t "$archive.part"
  mv "$archive.part" "$archive"
fi
if [[ ! -s "$decompressed" || "$archive" -nt "$decompressed" ]]; then
  gzip -dc "$archive" > "$decompressed"
fi

swiftc -O \
  -sdk "$sdk_path" \
  -module-cache-path "$module_cache" \
  "$project_dir/Sources/MATER/StockholmModel.swift" \
  "$project_dir/Sources/MATER/StructureModel.swift" \
  "$project_dir/Sources/MATER/CurationAnalysis.swift" \
  "$project_dir/Tests/RfamCorpusAuditMain.swift" \
  -o "$test_binary"

"$test_binary" "$decompressed" "$sample_count"
