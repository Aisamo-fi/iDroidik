#!/bin/bash
# Split a large image (e.g. the ~3 GB Android nand) into <1.9 GB parts that fit a
# GitHub release asset, plus a sha256 manifest. Reassemble with join-image.sh.
#
#   ./tools/split-image.sh <image-file> [out-dir] [part-size-bytes]
#
set -eu
SRC="${1:?usage: split-image.sh <image-file> [out-dir] [part-bytes]}"
OUT="${2:-nandparts}"
PART_BYTES="${3:-1900000000}"   # ~1.9 GB, under GitHub's 2 GB asset cap
[ -f "$SRC" ] || { echo "no such file: $SRC" >&2; exit 1; }
mkdir -p "$OUT"
base=$(basename "$SRC")

echo "splitting $SRC ($(du -h "$SRC" | cut -f1)) into ${PART_BYTES}-byte parts…"
# numeric suffixes: <base>.part00, .part01, …
split -b "$PART_BYTES" -d -a 2 "$SRC" "$OUT/$base.part"

echo "hashing whole image + parts…"
( cd "$OUT" && shasum -a 256 "$base".part* > "$base.parts.sha256" )
# hash by basename (cd into the source dir) so the file records "<hash>  <base>", not a local path
( cd "$(dirname "$SRC")" && shasum -a 256 "$base" ) | tee "$OUT/$base.whole.sha256"

echo
echo "done → $OUT/"
ls -la "$OUT"
echo
echo "Upload the .part* files + the .sha256 files to your host, then record the URLs"
echo "and hashes in MANIFEST.md and install.sh."
