#!/bin/bash
# Usage: ./boot.sh linux|android
# Boots Project Sandcastle: palera1n's native checkm8 + the old pongoOS extracted from
# checkra1n 0.10.1 (newer pongo can't load the Sandcastle image; 0.10.1 itself crashes on this macOS).
set -u
cd "$(dirname "$0")"
TARGET="${1:-linux}"
if [ "$TARGET" = android ]; then IMG=android-sandcastle/Android.lzma; DTB=android-sandcastle/dtbpack
else IMG=linux/Linux.lzma; DTB=linux/dtbpack; fi

OUT="$PWD/palera1n-$TARGET.out"
echo "[boot] palera1n -p -k Pongo-0.10.1.bin — put the iPhone into DFU"
"${PALERA1N:-$HOME/.local/bin/palera1n}" -p -k Pongo-0.10.1.bin -S -v < <(sleep 86400) > "$OUT" 2>&1 &
P=$!

last=""
while kill -0 $P 2>/dev/null; do
  line=$(grep -E "Found device|DFU|checkm8|Booting|Booted|pongo|Pongo|rror|Waiting" "$OUT" | tail -1)
  [ "$line" != "$last" ] && [ -n "$line" ] && echo "[palera1n] $line" && last="$line"
  sleep 1
done
echo "[boot] palera1n exited"
tail -5 "$OUT" | sed 's/^/[palera1n-tail] /'

sleep 3
echo "[boot] uploading $IMG"
./android-sandcastle/load-linux.mac "$IMG" "$DTB" 2>&1 | sed 's/^/[load-linux] /'
echo "[boot] load-linux exit ${PIPESTATUS[0]}"
echo "[boot] done"
