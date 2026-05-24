#!/usr/bin/env bash
set -euo pipefail

# Generate a GitHub release body listing packaged assets with file sizes and
# SHA256 checksums so desktop release pages stay self-describing.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_TAG="${1:-${TARGET_TAG:-}}"
ASSET_DIR="${2:-${ASSET_DIR:-$ROOT_DIR/dist/release}}"
OUTPUT_FILE="${3:-${OUTPUT_FILE:-$ROOT_DIR/dist/release-body.md}}"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

human_size() {
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B --format="%.1f" "$1"
    return
  fi
  printf '%sB\n' "$1"
}

main() {
  [[ -n "$TARGET_TAG" ]] || fail "TARGET_TAG is required"
  [[ -d "$ASSET_DIR" ]] || fail "Asset directory does not exist: $ASSET_DIR"
  require_cmd sha256sum

  mapfile -t assets < <(find "$ASSET_DIR" -maxdepth 1 -type f | sort)

  {
    printf '# 云卷 %s\n\n' "$TARGET_TAG"
    printf '## 构建产物\n\n'

    if [[ ${#assets[@]} -eq 0 ]]; then
      printf '%s\n' '- 暂无。'
    else
      for asset in "${assets[@]}"; do
        local basename size_bytes size_human checksum
        basename="$(basename "$asset")"
        size_bytes="$(stat -c %s "$asset" 2>/dev/null || stat -f %z "$asset")"
        size_human="$(human_size "$size_bytes")"
        checksum="$(sha256sum "$asset" | awk '{print $1}')"
        printf -- '- `%s`\n' "$basename"
        printf '  sha256: `%s`\n' "$checksum"
        printf '  size: `%s`\n' "$size_human"
      done
    fi
  } > "$OUTPUT_FILE"
}

main "$@"
