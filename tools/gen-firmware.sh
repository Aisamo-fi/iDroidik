#!/bin/bash
# T1 — Generate the touch + Wi-Fi firmware on the USER'S OWN device, from their own iOS.
#
# This project NEVER distributes Apple/Broadcom firmware. The firmware required to drive
# the iPhone 7 touchscreen and Wi-Fi is copied, at install time, from the user's own
# licensed iOS install onto the Android APFS volume at /usr/share/firmware — which is
# exactly where the (firmware-free) Android image expects to find it at runtime.
#
# Verified on-device 2026-10-10: the shipped `nand` image's /vendor, /system and /odm
# contain NO firmware; the firmware lives only on the Android APFS volume:
#   /usr/share/firmware/multitouch/D10.mtprops            (touch, iPhone 7 = D10)
#   /usr/share/firmware/wifi/C-4355__s-C0/*.trx,*.clmb,*.txcb,*.txt   (brcmfmac 4355)
#
# Requires: the iPhone booted into jailbroken iOS and reachable over SSH (see config.env).
# Run this ONCE per device, during first-time setup, before booting Android.
set -eu
cd "$(dirname "$0")/.."
[ -f ./config.env ] && . ./config.env
: "${IOS_IP:?set IOS_IP in config.env (phone must be on jailbroken iOS over SSH)}"
: "${IOS_SSH_PASS:=alpine}"; : "${SSHPASS_BIN:=sshpass}"
ssh_() { "$SSHPASS_BIN" -p "$IOS_SSH_PASS" ssh -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o LogLevel=ERROR "root@$IOS_IP" "$@"; }

echo "Mounting the Android volume on the phone (found by label, not a hardcoded node)..."
ssh_ '
if ! mount | grep -q " /var/mnt/android "; then
  mkdir -p /var/mnt/android
  DEV=""
  for d in /dev/disk0s1s*; do
    [ -b "$d" ] || continue
    [ "$(/System/Library/Filesystems/apfs.fs/apfs.util -p "$d" 2>/dev/null)" = "Android" ] && { DEV="$d"; break; }
  done
  [ -n "$DEV" ] || { echo "No APFS volume named Android found — run ./setup-device.sh first"; exit 1; }
  mount -t apfs "$DEV" /var/mnt/android
fi' || { echo "Could not mount the Android volume"; exit 1; }

echo "Copying firmware from THIS device's own iOS into the Android volume (nothing is downloaded)..."
ssh_ '
set -e
SRC=/usr/share/firmware
DST=/var/mnt/android/usr/share/firmware
[ -d "$SRC" ] || { echo "iOS firmware dir $SRC not found on this iOS build — report the iOS version"; exit 2; }
copied=0
for sub in multitouch wifi; do
  if [ -d "$SRC/$sub" ]; then
    mkdir -p "$DST/$sub"
    cp -a "$SRC/$sub/." "$DST/$sub/" && copied=1
    echo "  copied $sub"
  else
    echo "  (no $SRC/$sub on this iOS — skipping)"
  fi
done
sync
[ "$copied" = 1 ] || { echo "Nothing copied — no firmware found on iOS"; exit 3; }
echo "Firmware now on the Android volume:"; find "$DST" -type f | wc -l
'
echo "Done — touch + Wi-Fi firmware generated on-device from your own iOS."
echo "Nothing proprietary was downloaded or redistributed. Now you can boot Android: ./android.sh"
