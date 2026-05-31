#!/usr/bin/env bash
set -euo pipefail

# Build standalone CLI release artifacts for cross-platform distribution.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_PREFIX="${ARTIFACT_PREFIX:-yunjuan}"
OUTPUT_DIR="$ROOT_DIR/dist/cli"

GOOS_VALUE=""
GOARCH_VALUE=""
VERSION=""

usage() {
  cat <<'EOF'
Usage: ./scripts/build_cli_packages.sh --goos <linux|darwin|windows> --goarch <amd64|arm64> --version <x.y.z> [options]

Options:
  --goos <name>            Target GOOS
  --goarch <name>          Target GOARCH
  --version <x.y.z>        Release version embedded with ldflags
  --output-dir <path>      Output directory for packaged artifacts
  -h, --help               Show this help
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

resolve_output_dir() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$ROOT_DIR/$1" ;;
  esac
}

archive_name() {
  local goos="$1"
  local goarch="$2"
  case "$goos" in
    windows) printf '%s-cli-%s-%s.zip\n' "$ARTIFACT_PREFIX" "$goos" "$goarch" ;;
    *) printf '%s-cli-%s-%s.tar.gz\n' "$ARTIFACT_PREFIX" "$goos" "$goarch" ;;
  esac
}

binary_name() {
  case "$1" in
    windows) printf 'cloud-volume-cli.exe\n' ;;
    *) printf 'cloud-volume-cli\n' ;;
  esac
}

package_archive() {
  local stage_dir="$1"
  local archive_path="$2"
  local base_name
  base_name="$(basename "$stage_dir")"

  rm -f "$archive_path"
  case "$archive_path" in
    *.zip)
      (
        cd "$(dirname "$stage_dir")"
        zip -qr "$archive_path" "$base_name"
      )
      ;;
    *.tar.gz)
      tar -C "$(dirname "$stage_dir")" -czf "$archive_path" "$base_name"
      ;;
    *)
      fail "Unsupported archive format: $archive_path"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --goos)
      GOOS_VALUE="${2:-}"
      shift 2
      ;;
    --goarch)
      GOARCH_VALUE="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$(resolve_output_dir "${2:-}")"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$GOOS_VALUE" ]] || fail "--goos is required"
[[ -n "$GOARCH_VALUE" ]] || fail "--goarch is required"
[[ -n "$VERSION" ]] || fail "--version is required"

mkdir -p "$OUTPUT_DIR"

stage_root="$(mktemp -d)"
stage_dir="$stage_root/${ARTIFACT_PREFIX}-cli-${GOOS_VALUE}-${GOARCH_VALUE}"
mkdir -p "$stage_dir"

binary_path="$stage_dir/$(binary_name "$GOOS_VALUE")"

env \
  CGO_ENABLED=0 \
  GOOS="$GOOS_VALUE" \
  GOARCH="$GOARCH_VALUE" \
  go build \
  -trimpath \
  -ldflags "-s -w -X main.version=$VERSION" \
  -o "$binary_path" \
  ./cmd/cloud-volume-cli

cp "$ROOT_DIR/README.md" "$stage_dir/README.md"
archive_path="$OUTPUT_DIR/$(archive_name "$GOOS_VALUE" "$GOARCH_VALUE")"
package_archive "$stage_dir" "$archive_path"

rm -rf "$stage_root"
