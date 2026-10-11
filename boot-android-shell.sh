#!/bin/bash
# Waits for pongoOS (booted by `palera1n -p`), chainloads the official PongoOS 2.6.1
# (palera1n's build lacks the Linux commands), then uploads the Sandcastle kernel.
# Usage: ./wait-and-load.sh linux|android
cd "$(dirname "$0")"
TARGET="${1:-android}"
if [ "$TARGET" = android ]; then IMG=android-sandcastle/Android.lzma; DTB=android-sandcastle/dtbpack
else IMG=linux/Linux.lzma; DTB=linux/dtbpack; fi

pongo_present() { ioreg -p IOUSB -l -w0 | grep -q '"USB Product Name" = "PongoOS USB Device"'; }

echo "[wait] waiting for pongoOS USB device"
mode=""
until pongo_present; do
  u=$(ioreg -p IOUSB -l -w0 | grep -oE '"USB Product Name" = "[^"]+"' | grep -iE 'apple mobile|iphone' | tr '\n' ' ')
  [ "$u" != "$mode" ] && echo "[usb] ${u:-<none>}" && mode="$u"
  sleep 1
done
sleep 3

ver=$(./loader/pongo-shell 2>/dev/null | grep -oE 'pongoOS [0-9.]+' | head -1)
echo "[wait] found $ver"
if [ "$ver" != "pongoOS 2.6.1" ]; then
  echo "[wait] chainloading PongoOS 2.6.1"
  ./loader/pongo-bootr pongo-rel/Pongo-2.6.1.bin 2>&1 | sed 's/^/[bootr] /'
  sleep 3
  until pongo_present; do sleep 1; done
  sleep 2
  echo "[wait] now $(./loader/pongo-shell 2>/dev/null | grep -oE 'pongoOS [0-9.]+' | head -1)"
fi

echo "[wait] uploading $IMG"
INITRD=work/debug-initrd.cpio.gz ./loader/pongo-linux "$IMG" "$DTB" 2>&1 | sed 's/^/[load-linux] /'
echo "[wait] load-linux exit ${PIPESTATUS[0]}"
