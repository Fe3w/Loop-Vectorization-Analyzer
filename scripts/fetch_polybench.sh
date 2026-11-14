#!/usr/bin/env bash
# Fetch PolyBench/C 4.2.1-beta, verify its SHA-256, extract it.
#
# Usage: scripts/fetch_polybench.sh [dest]           (default: bench/polybench)
#        scripts/fetch_polybench.sh --verify-only FILE
#
# Writes <dest>/SOURCE (URL, sha256, fetch date). Idempotent: an existing
# tarball with the right checksum is not downloaded again. The tree is data:
# nothing in it is executed by LoopLens's scripts (they pass paths to clang).
set -euo pipefail
URL="https://downloads.sourceforge.net/project/polybench/polybench-c-4.2.1-beta.tar.gz"
SHA256="426519ee8443a5f2175de6a3e9328cda8917a5e33053d0e8f59855ab56d689a4"
TARBALL_NAME="polybench-c-4.2.1-beta.tar.gz"

verify() { # file -> 0 if the checksum matches
  local got
  got="$(sha256sum "$1" | cut -d' ' -f1)"
  if [ "$got" != "$SHA256" ]; then
    echo "error: checksum mismatch for $1: got $got, expected $SHA256" >&2
    return 1
  fi
}

if [ "${1:-}" = "--verify-only" ]; then
  verify "${2:?--verify-only needs a file}"
  echo "ok: $2"
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/bench/polybench}"
mkdir -p "$DEST"
TARBALL="$DEST/$TARBALL_NAME"

if [ -f "$TARBALL" ] && verify "$TARBALL" 2>/dev/null; then
  echo "tarball present and verified: $TARBALL"
else
  for attempt in 1 2 3; do
    if curl -fsSL --max-time 300 -o "$TARBALL.part" "$URL"; then break; fi
    echo "download attempt $attempt failed" >&2
    [ "$attempt" = 3 ] && { echo "error: download failed; fetch $URL manually into $DEST" >&2; exit 1; }
    sleep $((attempt * 5))
  done
  mv "$TARBALL.part" "$TARBALL"
  verify "$TARBALL"
fi

tar -xzf "$TARBALL" -C "$DEST"
printf 'url: %s\nsha256: %s\nfetched: %s\n' "$URL" "$SHA256" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DEST/SOURCE"
echo "extracted to $DEST/polybench-c-4.2.1-beta"
