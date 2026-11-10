#!/bin/bash
# Re-downloads the pinned Unicode/CLDR source files listed in Data/sources.tsv
# and verifies each download against the pinned sha256 and byte count.
#
#   scripts/fetch-unicode-data.sh            fetch into place, then verify
#   scripts/fetch-unicode-data.sh --verify   verify the files already on disk
#
# Exits 1 when any file fails to download or matches neither the checksum nor
# the byte count; downloads that mismatch are removed, not installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TSV="$ROOT/Data/sources.tsv"

verify_only=0
case "${1:-}" in
    "") ;;
    --verify) verify_only=1 ;;
    *) echo "usage: $0 [--verify]" >&2; exit 2 ;;
esac

check() {
    local path="$1" expected_sha="$2" expected_bytes="$3" actual actual_bytes
    actual="$(shasum -a 256 "$path" | awk '{print $1}')"
    actual_bytes="$(wc -c < "$path" | tr -d ' ')"
    [[ "$actual" == "$expected_sha" && "$actual_bytes" == "$expected_bytes" ]]
}

failures=0
while IFS=$'\t' read -r path url sha bytes; do
    case "$path" in ''|\#*) continue ;; esac
    dest="$ROOT/$path"
    if [[ "$verify_only" -eq 1 ]]; then
        if [[ ! -f "$dest" ]]; then
            echo "missing: $path" >&2
            failures=1
            continue
        fi
        if check "$dest" "$sha" "$bytes"; then
            echo "ok: $path"
        else
            echo "checksum mismatch: $path" >&2
            failures=1
        fi
        continue
    fi
    mkdir -p "$(dirname "$dest")"
    tmp="$dest.download.$$"
    trap 'rm -f "$tmp"' EXIT
    if ! curl -fsSL --retry 3 -o "$tmp" "$url"; then
        echo "download failed: $url" >&2
        rm -f "$tmp"
        failures=1
        trap - EXIT
        continue
    fi
    if check "$tmp" "$sha" "$bytes"; then
        mv "$tmp" "$dest"
        trap - EXIT
        echo "fetched: $path"
    else
        echo "checksum mismatch: $path (not installed)" >&2
        rm -f "$tmp"
        trap - EXIT
        failures=1
    fi
done < "$TSV"

exit "$failures"
