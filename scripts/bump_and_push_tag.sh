#!/usr/bin/env bash
# Creates the next semver git tag after the latest v* tag and pushes branch + tag.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUMP_KIND="${BUMP:-patch}" # patch | minor | major

die() {
  echo "bump_and_push_tag: $*" >&2
  exit 1
}

latest_tag() {
  local tags
  tags="$(git tag -l 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null | sort -V)"
  echo "$tags" | tail -n 1
}

parse_semver() {
  local raw="${1#v}"
  if [[ ! "$raw" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "invalid semver tag: $1"
  fi
  IFS=. read -r MAJOR MINOR PATCH <<<"$raw"
}

next_tag() {
  local base="$1"
  if [[ -z "$base" ]]; then
    echo "v0.0.1"
    return
  fi
  parse_semver "$base"
  case "$BUMP_KIND" in
    major)
      echo "v$((MAJOR + 1)).0.0"
      ;;
    minor)
      echo "v${MAJOR}.$((MINOR + 1)).0"
      ;;
    patch)
      echo "v${MAJOR}.${MINOR}.$((PATCH + 1))"
      ;;
    *)
      die "unknown BUMP=$BUMP_KIND (use patch, minor, or major)"
      ;;
  esac
}

if [[ -n "$(git status --porcelain)" && "${FORCE:-}" != "1" ]]; then
  die "working tree is dirty; commit or stash first, or FORCE=1 to ignore"
fi

current="$(latest_tag)"
new_tag="$(next_tag "$current")"

if git rev-parse "$new_tag" >/dev/null 2>&1; then
  die "tag $new_tag already exists"
fi

echo "Latest tag: ${current:-<none>}"
echo "New tag:    $new_tag"
echo "Pushing:    $(git branch --show-current) + $new_tag"

git tag -a "$new_tag" -m "Release $new_tag"
git push origin HEAD
git push origin "$new_tag"

echo "Done. GitHub Actions release should run for $new_tag."
