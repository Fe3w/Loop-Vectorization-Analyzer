#!/usr/bin/env bash
# Unpack Ubuntu's AArch64 cross libc headers into a local sysroot, without
# installing anything (apt-get download + dpkg -x; no root needed), so clang
# can compile PolyBench for --target=aarch64-linux-gnu. Compile-only: nothing
# is linked or run for AArch64.
#
# Usage: scripts/fetch_aarch64_sysroot.sh [dest]   (default: bench/sysroot-aarch64)
# Prints the --sysroot directory.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/bench/sysroot-aarch64}"
mkdir -p "$DEST/deb" "$DEST/root"
( cd "$DEST/deb" && apt-get download libc6-dev-arm64-cross linux-libc-dev-arm64-cross libc6-arm64-cross >/dev/null 2>&1 )
for f in "$DEST"/deb/*.deb; do dpkg -x "$f" "$DEST/root"; done
ls "$DEST"/deb/*.deb | xargs -n1 basename > "$DEST/SOURCE"
echo "$DEST/root/usr/aarch64-linux-gnu"
