#!/bin/bash
# Uploads nand-a16 to the phone's Android volume as /nand (jailbroken iOS over SSH) and verifies sha256.
set -eu
cd "$(dirname "$0")/.."
[ -f ./config.env ] && . ./config.env
: "${IOS_IP:?set IOS_IP in config.env}"; : "${IOS_SSH_PASS:=alpine}"; : "${SSHPASS_BIN:=sshpass}"
SP="$SSHPASS_BIN"
PHONE="root@$IOS_IP"
ssh_() { $SP -p "$IOS_SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o LogLevel=ERROR "$@"; }
ssh_ "$PHONE" 'mkdir -p /var/mnt/android; mount | grep -q " /var/mnt/android " || for d in /dev/disk0s1s*; do [ "$(/System/Library/Filesystems/apfs.fs/apfs.util -p "$d" 2>/dev/null)" = Android ] && { mount -t apfs "$d" /var/mnt/android; break; }; done; ls -l /var/mnt/android'
echo "uploading nand-a16 (3.1 GB, usually 1-3 minutes)..."
ssh_ -C "$PHONE" 'cat > /var/mnt/android/nand.part && sync' < nand-a16
echo "verifying the checksum (~1 min)..."
want=$(cut -d' ' -f1 nand-a16.sha256)
got=$(ssh_ "$PHONE" '{ sha256sum /var/mnt/android/nand.part 2>/dev/null || shasum -a 256 /var/mnt/android/nand.part; }' | cut -d' ' -f1)
echo "expected  $want"; echo "on phone  $got"
if [ "$want" = "$got" ]; then
  ssh_ "$PHONE" 'cd /var/mnt/android && mv -f nand.part nand && sync && cd / && umount /var/mnt/android'
  echo "✓ Android 16 updated on the phone"
else
  echo "✗ MISMATCH, nand not replaced"; exit 1
fi
