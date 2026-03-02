#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
notes_file="${2:-docs/RELEASES.md}"

if [[ -z "${version}" ]]; then
  echo "usage: $0 <version> [notes_file]" >&2
  exit 1
fi

version_header="$(grep -E "^${version}( \([0-9]{4}-[0-9]{2}-[0-9]{2}\))?$" "$notes_file" | head -n1 || true)"

if [[ -n "$version_header" ]]; then
  awk -v start_line="$version_header" '
    $0 == start_line {in_block=1; print; next}
    in_block && $0 ~ /^v[0-9]+\.[0-9]+\.[0-9]+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$/ {exit}
    in_block {print}
  ' "$notes_file"
  exit 0
fi

if grep -qx "Unreleased" "$notes_file"; then
  awk '
    $0 == "Unreleased" {in_block=1; print; next}
    in_block && $0 ~ /^v[0-9]+\.[0-9]+\.[0-9]+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$/ {exit}
    in_block {print}
  ' "$notes_file"
  exit 0
fi

echo "No release notes found for $version and no Unreleased section in $notes_file" >&2
exit 1
