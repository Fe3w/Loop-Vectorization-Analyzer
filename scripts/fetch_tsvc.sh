#!/usr/bin/env bash
# Fetch TSVC_2 (UoB-HPC) at a pinned commit: src/tsvc.c, src/common.h,
# src/array_defs.h, each SHA-256 checked. Writes <dest>/benchmark_list (for
# scripts/collect.sh --list) and <dest>/SOURCE.
#
# Usage: scripts/fetch_tsvc.sh [dest]                       (default: bench/tsvc)
#        scripts/fetch_tsvc.sh --verify-only <name> FILE   (name: tsvc.c, common.h, array_defs.h)
#
# Licence: the TSVC_2 repository publishes no licence file (checked 2026-11-12).
# LoopLens never commits or redistributes these sources; it only downloads and
# compiles them locally to measure LoopVectorize's behaviour.
set -euo pipefail
COMMIT="911fc639b933df38a7728477ce4b2e68e9c8eeff"
BASE="https://raw.githubusercontent.com/UoB-HPC/TSVC_2/$COMMIT/src"
declare -A SHA=(
  [tsvc.c]=d87fdcf902720c09f1191fd310f5b80e1c95a1fd48394d6cced7cd78ad01a8af
  [common.h]=31020e3037f586617c2bf6c1e0e310285e2cbd0cdb7259eeaa9c464a45035d5f
  [array_defs.h]=fa2c6a8d138d0eeaa129ebe4df4454e2ac8fe2a03023cbb9f6aefd7f31f9b8ec
)

verify() { # name file
  local want="${SHA[$1]:?unknown file $1}" got
  got="$(sha256sum "$2" | cut -d' ' -f1)"
  if [ "$got" != "$want" ]; then
    echo "error: checksum mismatch for $2: got $got, expected $want" >&2
    return 1
  fi
}

if [ "${1:-}" = "--verify-only" ]; then
  verify "${2:?name}" "${3:?file}"; echo "ok: $3"; exit 0
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/bench/tsvc}"
mkdir -p "$DEST"
for f in tsvc.c common.h array_defs.h; do
  if [ -f "$DEST/$f" ] && verify "$f" "$DEST/$f" 2>/dev/null; then continue; fi
  for attempt in 1 2 3; do
    if curl -fsSL --max-time 120 -o "$DEST/$f.part" "$BASE/$f"; then break; fi
    [ "$attempt" = 3 ] && { echo "error: download of $f failed; fetch $BASE/$f manually" >&2; exit 1; }
    sleep $((attempt * 5))
  done
  mv "$DEST/$f.part" "$DEST/$f"
  verify "$f" "$DEST/$f"
done
echo "./tsvc.c" > "$DEST/benchmark_list"
{
  echo "repo: https://github.com/UoB-HPC/TSVC_2"
  echo "commit: $COMMIT"
  for f in tsvc.c common.h array_defs.h; do echo "sha256 $f: ${SHA[$f]}"; done
  echo "licence: none published in the repository (checked 2026-11-12); not redistributed"
  echo "fetched: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$DEST/SOURCE"
echo "TSVC_2 sources in $DEST"
