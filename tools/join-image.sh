#!/bin/bash
# Reassemble an image split by split-image.sh, verifying every part and the whole.
#
#   ./tools/join-image.sh <parts-dir> <base-name> <output-file>
#   e.g. ./tools/join-image.sh nandparts nand-a16 nand-a16
#
set -eu
DIR="${1:?usage: join-image.sh <parts-dir> <base-name> <output-file>}"
BASE="${2:?base name, e.g. nand-a16}"
OUT="${3:?output file}"

[ -f "$DIR/$BASE.parts.sha256" ] || { echo "missing $DIR/$BASE.parts.sha256" >&2; exit 1; }

echo "verifying parts…"
( cd "$DIR" && shasum -a 256 -c "$BASE.parts.sha256" )

echo "joining → $OUT…"
# deterministic: always write to $OUT (as given); parts are read from $DIR
cat "$DIR/$BASE".part* > "$OUT"

if [ -f "$DIR/$BASE.whole.sha256" ]; then
  echo "verifying whole image…"
  want=$(cut -d' ' -f1 "$DIR/$BASE.whole.sha256")
  got=$(shasum -a 256 "$OUT" | cut -d' ' -f1)
  [ "$want" = "$got" ] && echo "✓ image OK ($got)" || { echo "✗ whole-image sha mismatch" >&2; exit 1; }
fi
echo "done → $OUT"
