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
# ATOMIC: assemble into a temp file and rename to $OUT only after the whole-image sha
# verifies. A failed or interrupted join (ENOSPC, Ctrl-C) then leaves NO $OUT, so a re-run
# re-downloads/re-joins instead of mistaking a truncated file for "already present".
TMP="$OUT.join.$$"
trap 'rm -f "$TMP"' EXIT
cat "$DIR/$BASE".part* > "$TMP"

if [ -f "$DIR/$BASE.whole.sha256" ]; then
  echo "verifying whole image…"
  want=$(cut -d' ' -f1 "$DIR/$BASE.whole.sha256")
  got=$(shasum -a 256 "$TMP" | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "✗ whole-image sha mismatch" >&2; exit 1; }
  echo "✓ image OK ($got)"
fi
mv -f "$TMP" "$OUT"
trap - EXIT
echo "done → $OUT"
