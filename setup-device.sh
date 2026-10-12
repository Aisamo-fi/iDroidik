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
#   4) provision a persistent /data (userdata.img) by default so apps/settings survive reboots
#      (falls back to RAM if the phone is low on space, or with NO_PERSIST=1);
#   5) tell you to boot with ./android.sh.
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

bold "1/5  Checking the phone (must be jailbroken iOS, iPhone 7)…"
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

bold "2/5  Finding or creating the 'Android' APFS volume (additive, iOS is not touched)…"
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

bold "3/5  Uploading the firmware-free image to the phone (~3 GB, a few minutes)…"
want=$(shasum -a 256 "$IMAGE" | cut -d' ' -f1)
# Skip the upload on a re-run if the phone already has exactly this image (computing the
# device-side sha of ~3 GB takes ~1 min but saves a multi-minute re-upload, and avoids a
# misleading "not enough space" when userdata.img has since taken the slack).
have=$(ios '{ sha256sum /var/mnt/android/nand 2>/dev/null || shasum -a 256 /var/mnt/android/nand 2>/dev/null; }' | cut -d' ' -f1)
if [ -n "$have" ] && [ "$have" = "$want" ]; then
  ok "image already on the phone and matches ($want) — skipping upload"
else
  # refuse if the phone doesn't have room — iOS and Android share the APFS container, so an
  # overflow would hurt iOS, not just Android.
  img_kb=$(( $(wc -c < "$IMAGE") / 1024 ))
  free_kb=$(ios "df -k /var/mnt/android 2>/dev/null | awk 'NR==2{print \$4}'" 2>/dev/null | tr -d '\r')
  case "$free_kb" in
    ''|*[!0-9]*) die "could not read free space on the phone (df failed) — refusing to upload a 3 GB image blind. iOS and Android share the APFS container, so this must be confirmed; check the phone's SSH and re-run." ;;
    *) [ "$free_kb" -gt $((img_kb + 1048576)) ] || die "not enough space on the phone: need ~$((img_kb/1024)) MB + ~1 GB headroom, have ~$((free_kb/1024)) MB. iOS and Android share the APFS container — free space in iOS first." ;;
  esac
  "$SSHPASS_BIN" -p "$IOS_SSH_PASS" ssh -C -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o PubkeyAuthentication=no -o LogLevel=ERROR "root@$IOS_IP" 'cat > /var/mnt/android/nand.part && sync' < "$IMAGE" \
    || { ios 'rm -f /var/mnt/android/nand.part'; die "image transfer interrupted"; }
  got=$(ios '{ sha256sum /var/mnt/android/nand.part 2>/dev/null || shasum -a 256 /var/mnt/android/nand.part; }' | cut -d' ' -f1)
  [ "$want" = "$got" ] || { ios 'rm -f /var/mnt/android/nand.part'; die "checksum mismatch after upload (expected $want, got $got)"; }
  ios 'cd /var/mnt/android && mv -f nand.part nand && sync'
  ok "image on phone, checksum verified"
fi

bold "4/5  Generating touch + Wi-Fi firmware on-device from your own iOS…"
./tools/gen-firmware.sh || die "firmware generation failed (see docs/FIRMWARE-AND-LEGAL.md)"

# 5/5  Provision persistent /data (userdata.img). The kernel mounts APFS read-only, so a plain
# /data would live in RAM and be wiped every reboot. We create a file on the Android volume whose
# 4K blocks are each tagged (nonce + index); on boot the image's own scdata/sc-userdata.sh finds
# those blocks on the raw disk, device-mapper-maps exactly them, and formats ext4 there — iOS and
# APFS metadata are never written. ./android.sh reads the nonce from userdata-a16.conf and passes
# androidboot.sc_userdata=<nonce> on the kernel cmdline. Set NO_PERSIST=1 to skip (then /data is RAM).
# NOTE: the block format + sizing here mirror android.sh's ensure_userdata_img() — keep in sync.
bold "5/5  Provisioning persistent /data (userdata.img)…"
# re-mount the Android volume by label if gen-firmware left it unmounted
ios 'mkdir -p /var/mnt/android; mount | grep -q /var/mnt/android || for d in /dev/disk0s1s*; do [ "$(/System/Library/Filesystems/apfs.fs/apfs.util -p "$d" 2>/dev/null)" = Android ] && { mount -t apfs "$d" /var/mnt/android; break; }; done' || die "the Android volume did not mount"
if [ "${NO_PERSIST:-0}" = 1 ]; then
  warn "NO_PERSIST=1 — skipping persistent storage; /data will be in RAM (wiped on every reboot)"
elif [ -n "$(ios 'ls -ln /var/mnt/android/userdata.img 2>/dev/null' | awk '{print $5}')" ]; then
  if [ -f ./userdata-a16.conf ] && grep -q '^UD_NONCE=.' ./userdata-a16.conf; then
    ok "userdata.img already exists on the phone — keeping it (persistent /data)"
  else
    warn "userdata.img exists on the phone but local userdata-a16.conf has no nonce, so android.sh"
    warn "cannot address it and /data will be in RAM. Delete the phone's userdata.img to re-provision."
  fi
else
  free_gb=$(ios 'df -k /var/mnt/android 2>/dev/null' | awk 'NR==2{print int($4/1048576)}')
  gb=${USERDATA_GB:-6}
  # USERDATA_GB must be a whole number >=2, or the mapper rejects a too-small image and /data
  # silently falls back to RAM (0 = 0 would otherwise pass the size check).
  case "$gb" in ''|*[!0-9]*) die "USERDATA_GB must be a whole number of GB (got '$gb'); or set NO_PERSIST=1" ;; esac
  [ "$gb" -ge 2 ] || die "USERDATA_GB must be >= 2 (got $gb); or set NO_PERSIST=1 to skip persistence"
  case "$free_gb" in ''|*[!0-9]*) free_gb=0 ;; esac
  # Need >=3 GB headroom for iOS PLUS >=2 GB for /data. If we cannot CONFIRM that (df
  # unreadable -> free_gb=0, or genuinely too little), do NOT write — fall back to RAM.
  # This is fail-safe: never create a multi-GB file in the shared APFS container blind.
  if [ "$free_gb" -lt 5 ]; then
    warn "couldn't confirm enough free space on the phone (read ${free_gb} GB; need >=5) — NOT"
    warn "creating userdata.img; /data will be in RAM. Free space in iOS and re-run for persistence."
  else
    [ $((free_gb - 3)) -lt "$gb" ] && gb=$((free_gb - 3))
    nonce=$(openssl rand -hex 8)
    echo "  creating a ${gb} GB userdata.img (keeping ≥3 GB for iOS), ~3-8 min…"
    # each 4096-byte block = "SCUDATA1" + <nonce,index,total> little-endian u64 x3 + padding
    python3 -c '
import sys, struct
nonce, total = int(sys.argv[1], 16), int(sys.argv[2]) * 262144
out = sys.stdout.buffer; pad = bytes(4064)
for i in range(total):
    out.write(b"SCUDATA1" + struct.pack("<QQQ", nonce, i, total) + pad)
' "$nonce" "$gb" | "$SSHPASS_BIN" -p "$IOS_SSH_PASS" ssh -C -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o PubkeyAuthentication=no -o LogLevel=ERROR "root@$IOS_IP" 'cat > /var/mnt/android/userdata.img.part && sync' \
      || { ios 'rm -f /var/mnt/android/userdata.img.part'; die "userdata.img transfer interrupted"; }
    got=$(ios 'ls -ln /var/mnt/android/userdata.img.part 2>/dev/null' | awk '{print $5}')
    [ "$got" = $((gb * 1073741824)) ] || { ios 'rm -f /var/mnt/android/userdata.img.part'; die "userdata.img has the wrong size ($got)"; }
    ios 'cd /var/mnt/android && mv -f userdata.img.part userdata.img && sync' || die "failed to finalize userdata.img"
    printf 'UD_NONCE=%s\nUD_HDR=\n' "$nonce" > ./userdata-a16.conf
    ok "persistent /data provisioned (${gb} GB) — apps, settings and the Pixel look will survive reboots"
    echo "  (the FIRST Android boot takes ~1.5 min longer while it locates the blocks)"
  fi
fi
ios 'sync; cd / && umount /var/mnt/android' >/dev/null 2>&1 || true

echo
ok "Device prepared. Now boot Android:"
bold "   ./android.sh"
echo "(First boot applies performance tuning. If persistent storage was provisioned above, your"
echo " apps and settings survive reboots; if it fell back to RAM, /data resets each boot. You can"
echo " re-run with NO_PERSIST=1 to force RAM, or USERDATA_GB=N to size the persistent store.)"
