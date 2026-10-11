#!/bin/bash
# ⚠️ EXPERIMENTAL first-time device setup — assembles the whole on-device bring-up into
# one script. It has NOT been tested end-to-end on a fresh device yet; read what it does
# before running, and prefer running it under an AI agent that can watch each step
# (see SETUP-WITH-AI.md).
#
# What it does, on an iPhone 7 (iPhone9,1 / iPhone9,3) running jailbroken iOS 15 over SSH:
#   1) find or CREATE an APFS volume named "Android" in the iOS container (additive —
#      it does NOT erase iOS; this is exactly what Project Sandcastle's setup does);
#   2) copy the firmware-free Android image (local ./nand-a16) onto that volume as /nand;
#   3) generate the touch + Wi-Fi firmware ON THE DEVICE from the user's own iOS
#      (tools/gen-firmware.sh);
#   4) tell you to boot with ./android.sh. (Persistent /data is NOT provisioned here — a plain
#      boot uses a RAM /data; see the note printed at the end.)
#
# SAFETY: never restores/erases the iPhone; only ADDS an APFS volume and writes files to it.
# If the device is not an iPhone 7, or not on jailbroken iOS over SSH, it stops.
set -eu
cd "$(dirname "$0")"
[ -f ./config.env ] && . ./config.env
: "${IOS_IP:?set IOS_IP in config.env — the iPhone must be on jailbroken iOS, reachable over SSH}"
: "${IOS_SSH_PASS:=alpine}"; : "${SSHPASS_BIN:=sshpass}"
IMAGE="${NAND:-nand-a16}"

bold(){ printf '\033[1m%s\033[0m\n' "$*"; }
ok(){ printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn(){ printf '\033[33m! %s\033[0m\n' "$*"; }
die(){ printf '\033[31m✗ %s\033[0m\n' "$*"; exit 1; }
ios(){ "$SSHPASS_BIN" -p "$IOS_SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PubkeyAuthentication=no -o LogLevel=ERROR "root@$IOS_IP" "$@"; }

bold "iDroidik first-time device setup (EXPERIMENTAL)"
[ -f "$IMAGE" ] || die "image '$IMAGE' not found — run ./install.sh first to fetch it"

bold "1/4  Checking the phone (must be jailbroken iOS, iPhone 7)…"
ios true 2>/dev/null || die "cannot SSH to root@$IOS_IP — boot the phone into jailbroken iOS (palera1n -f) and set IOS_IP"
MODEL=$(ios 'uname -a; /usr/bin/sysctl -n hw.machine 2>/dev/null || true' 2>/dev/null || true)
echo "  device: $MODEL"
case "$MODEL" in
  *iPhone9,1*|*iPhone9,3*) ok "iPhone 7 detected" ;;
  *) die "this is NOT an iPhone 7 (iPhone9,1 / iPhone9,3) — this project ONLY supports the iPhone 7. Stopping." ;;
esac
IOSVER=$(ios 'plutil -extract ProductVersion raw /System/Library/CoreServices/SystemVersion.plist 2>/dev/null || sw_vers -productVersion 2>/dev/null || grep -a -oE "1[0-9]\.[0-9]+(\.[0-9]+)?" /System/Library/CoreServices/SystemVersion.plist 2>/dev/null | head -1' 2>/dev/null | tr -d '\r' | head -1)
echo "  iOS: ${IOSVER:-unknown}"
case "$IOSVER" in
  15.*) ok "iOS 15 detected" ;;
  '')   warn "could not read the iOS version — continuing, but this is only tested on iOS 15.x" ;;
  *)    die "iOS $IOSVER is not supported — this project targets iOS 15.x only. Stopping." ;;
esac

bold "2/4  Finding or creating the 'Android' APFS volume (additive, iOS is not touched)…"
find_android_dev() {
  ios 'for d in /dev/disk0s1s*; do [ -b "$d" ] || continue; \
        [ "$(/System/Library/Filesystems/apfs.fs/apfs.util -p "$d" 2>/dev/null)" = "Android" ] && { echo "$d"; break; }; done'
}
DEV=$(find_android_dev || true)
if [ -z "${DEV:-}" ]; then
  warn "no 'Android' volume yet — creating one (newfs_apfs, adds a volume to the existing container)"
  ios 'newfs_apfs -A -v Android -e /dev/disk0s1' || die "failed to create the Android volume"
  DEV=$(find_android_dev || true)
fi
[ -n "${DEV:-}" ] || die "could not find the Android volume after creating it"
ok "Android volume: $DEV"
ios "mkdir -p /var/mnt/android; mount | grep -q /var/mnt/android || mount -t apfs $DEV /var/mnt/android" || die "failed to mount the Android volume"

bold "3/4  Uploading the firmware-free image to the phone (~3 GB, a few minutes)…"
# refuse if the phone doesn't have room — iOS and Android share the APFS container, so an
# overflow would hurt iOS, not just Android.
img_kb=$(( $(wc -c < "$IMAGE") / 1024 ))
free_kb=$(ios "df -k /var/mnt/android 2>/dev/null | awk 'NR==2{print \$4}'" 2>/dev/null | tr -d '\r')
case "$free_kb" in
  ''|*[!0-9]*) warn "could not read free space on the phone — continuing (watch for errors)" ;;
  *) [ "$free_kb" -gt $((img_kb + 1048576)) ] || die "not enough space on the phone: need ~$((img_kb/1024)) MB + ~1 GB headroom, have ~$((free_kb/1024)) MB. iOS and Android share the APFS container — free space in iOS first." ;;
esac
want=$(shasum -a 256 "$IMAGE" | cut -d' ' -f1)
"$SSHPASS_BIN" -p "$IOS_SSH_PASS" ssh -C -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o PubkeyAuthentication=no -o LogLevel=ERROR "root@$IOS_IP" 'cat > /var/mnt/android/nand.part && sync' < "$IMAGE" \
  || { ios 'rm -f /var/mnt/android/nand.part'; die "image transfer interrupted"; }
got=$(ios '{ sha256sum /var/mnt/android/nand.part 2>/dev/null || shasum -a 256 /var/mnt/android/nand.part; }' | cut -d' ' -f1)
[ "$want" = "$got" ] || { ios 'rm -f /var/mnt/android/nand.part'; die "checksum mismatch after upload (expected $want, got $got)"; }
ios 'cd /var/mnt/android && mv -f nand.part nand && sync'
ok "image on phone, checksum verified"

bold "4/4  Generating touch + Wi-Fi firmware on-device from your own iOS…"
./tools/gen-firmware.sh || die "firmware generation failed (see docs/FIRMWARE-AND-LEGAL.md)"
ios 'sync; cd / && umount /var/mnt/android' >/dev/null 2>&1 || true

echo
ok "Device prepared. Now boot Android:"
bold "   ./android.sh"
echo "(First boot applies performance tuning. NOTE: this experimental setup does not yet"
echo " provision persistent /data — a fresh boot uses a RAM-backed /data that resets on"
echo " reboot. Persistent storage currently needs the advanced './android.sh deploy' path.)"
