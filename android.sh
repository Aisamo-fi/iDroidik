#!/bin/bash
# Android (Project Sandcastle) on the iOS 15 iPhone 7 — one-command boot + tuning.
#
#   ./android.sh            boot Android and tune it (default)
#   ./android.sh save       copy Android /data to the Mac (restored automatically on next boot)
#   ./android.sh restore    put the saved /data back into a running Android
#   ./android.sh tune       re-apply performance tweaks to a running Android
#   ./android.sh linux      boot the Sandcastle Linux build instead
#   ./android.sh deploy     Android 16 loop: jailbroken iOS → upload nand-a16 if changed → Recovery → boot
#
# Boot chain: palera1n -p (checkm8 → palera1n's pongoOS 2.6.3, which lacks Linux commands)
#   → chainload official PongoOS 2.6.1 (bootr) → upload kernel with explicit linux_cmdline.
set -u
cd "$(dirname "$0")"

# ---------- user configuration ----------
# Copy config.env.example to config.env and edit it for your machine/phone.
# All personal values (phone IP, tool paths, root password) live there, not here.
[ -f ./config.env ] && . ./config.env
PALERA1N="${PALERA1N:-$HOME/.local/bin/palera1n}"   # path to the palera1n binary
IOS_IP="${IOS_IP:-}"                                # your iPhone's SSH IP while jailbroken (deploy/save)
IOS_SSH_PASS="${IOS_SSH_PASS:-alpine}"              # jailbreak root password (default: alpine)
SSHPASS_BIN="${SSHPASS_BIN:-sshpass}"              # sshpass binary (in PATH by default)
# The phone's nand holds Android 16 now; SYSTEM=a10 KERNEL=android-sandcastle/Android.lzma for the old one.
SYSTEM=${SYSTEM:-a16}
if [ "$SYSTEM" = a16 ]; then ANDROID_IMG=${KERNEL:-work/Image-a16f.lzma}; else ANDROID_IMG=${KERNEL:-android-sandcastle/Android.lzma}; fi
ANDROID_DTB=android-sandcastle/dtbpack
# The first successful Android boot was done with this initrd attached; keep the known-good setup.
ANDROID_INITRD=work/debug-initrd.cpio.gz
LINUX_IMG=linux/Linux.lzma
LINUX_DTB=linux/dtbpack

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()    { printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn()  { printf '\033[33m! %s\033[0m\n' "$*"; }
fail()  { printf '\033[31m✗ %s\033[0m\n' "$*"; exit 1; }

# adb root restarts adbd; macOS sometimes loses the re-enumerated gadget until the adb server restarts.
# Prefer an already-connected Wi-Fi ADB (stable); otherwise the USB gadget.
pick_device() {
  local wifi; wifi=$(adb devices 2>/dev/null | awk '$2=="device" && $1 ~ /:5555$/ {print $1; exit}')
  if [ -n "$wifi" ] && adb -s "$wifi" shell true >/dev/null 2>&1; then export ANDROID_SERIAL="$wifi"; return; fi
  [ -n "$wifi" ] && adb disconnect "$wifi" >/dev/null 2>&1
  local usb; usb=$(adb devices 2>/dev/null | awk '$2=="device" && $1 !~ /:/ {print $1; exit}')
  if [ -n "$usb" ]; then export ANDROID_SERIAL="$usb"; else unset ANDROID_SERIAL; fi
}
adb_ready() {
  for _ in 1 2 3; do
    for _ in $(seq 1 15); do pick_device; [ -n "${ANDROID_SERIAL:-}" ] && return 0; sleep 2; done
    adb kill-server >/dev/null 2>&1; adb start-server >/dev/null 2>&1
  done
  return 1
}
ensure_root() {
  adb_ready || fail "ADB is not responding"
  [ "$(adb shell id -u 2>/dev/null | tr -d '\r')" = "0" ] && return 0
  adb root >/dev/null 2>&1; sleep 3
  adb_ready || fail "ADB did not come back after adb root"
  [ "$(adb shell id -u 2>/dev/null | tr -d '\r')" = "0" ] || fail "failed to get root in Android"
}

# The Sandcastle USB gadget dies as soon as the phone sends data faster than a trickle, so bulk
# transfers go over ADB-over-Wi-Fi (the phone must be on the same network as the Mac).
use_wifi_adb() {
  # only an already-working *Wi-Fi* connection counts; the USB serial must not short-circuit this
  case "${ANDROID_SERIAL:-}" in *:5555) adb -s "$ANDROID_SERIAL" shell true >/dev/null 2>&1 && return 0 ;; esac
  adb_ready || fail "ADB is not responding"
  local ip; ip=$(adb shell "ip -4 addr show wlan0" 2>/dev/null | grep -oE 'inet [0-9.]+' | cut -d' ' -f2)
  [ -n "$ip" ] || fail "Android is not on Wi-Fi. Connect it to the same network as the Mac"
  if ! nc -z -G 3 "$ip" 5555 >/dev/null 2>&1; then
    # listen on TCP as well; adbd keeps serving USB after this restart
    adb shell "setprop service.adb.tcp.port 5555; setprop ctl.restart adbd" >/dev/null 2>&1
    sleep 5
  fi
  adb connect "$ip:5555" >/dev/null 2>&1
  adb -s "$ip:5555" shell true >/dev/null 2>&1 || fail "could not connect to Android over Wi-Fi ($ip). Are the Mac and phone on the same network?"
  export ANDROID_SERIAL="$ip:5555"
  ok "ADB over Wi-Fi: $ip"
}

# Even over Wi-Fi a long single stream from the phone stalls after ~6 MB, so move 4 MB verified chunks.
CHUNK_MB=4
t() { perl -e 'alarm shift; exec @ARGV' "$@"; } # run with a timeout in seconds

pull_file() { # remote local
  local size; size=$(t 20 adb shell stat -c %s "$1" 2>/dev/null | tr -d '\r')
  [ -n "$size" ] || return 1
  local chunks=$(( (size + CHUNK_MB*1048576 - 1) / (CHUNK_MB*1048576) )) i try part=$(mktemp) remote
  : > "$2"
  for ((i = 0; i < chunks; i++)); do
    for try in 1 2 3 4 5; do
      t 30 adb exec-out "dd if='$1' bs=1048576 skip=$((i*CHUNK_MB)) count=$CHUNK_MB 2>/dev/null" > "$part" 2>/dev/null
      remote=$(t 30 adb shell "dd if='$1' bs=1048576 skip=$((i*CHUNK_MB)) count=$CHUNK_MB 2>/dev/null | md5sum" 2>/dev/null | cut -d' ' -f1)
      [ -n "$remote" ] && [ "$(md5 -q "$part")" = "$remote" ] && break
      echo "  chunk $((i+1)) failed, retry $try"
      [ $try = 5 ] && { rm -f "$part"; return 1; }
      sleep 2
    done
    cat "$part" >> "$2"
    echo "  transfer: $(( (i + 1) * 100 / chunks ))%"
  done
  rm -f "$part"
  [ "$(stat -f %z "$2")" = "$size" ]
}

push_file() { # local remote
  local size; size=$(stat -f %z "$1")
  local chunks=$(( (size + CHUNK_MB*1048576 - 1) / (CHUNK_MB*1048576) )) i try part=$(mktemp)
  t 20 adb shell "rm -f '$2' /data/local/tmp/chunk" >/dev/null 2>&1
  for ((i = 0; i < chunks; i++)); do
    dd if="$1" of="$part" bs=1048576 skip=$((i*CHUNK_MB)) count=$CHUNK_MB 2>/dev/null
    for try in 1 2 3 4 5; do
      if t 60 adb push "$part" /data/local/tmp/chunk >/dev/null 2>&1 &&
         [ "$(t 30 adb shell md5sum /data/local/tmp/chunk 2>/dev/null | cut -d' ' -f1)" = "$(md5 -q "$part")" ] &&
         t 30 adb shell "cat /data/local/tmp/chunk >> '$2' && rm /data/local/tmp/chunk" >/dev/null 2>&1; then
        break
      fi
      echo "  chunk $((i+1)) failed, retry $try"
      [ $try = 5 ] && { rm -f "$part"; return 1; }
      sleep 2
    done
    echo "  transfer: $(( (i + 1) * 100 / chunks ))%"
  done
  rm -f "$part"
  [ "$(t 20 adb shell stat -c %s "$2" 2>/dev/null | tr -d '\r')" = "$size" ]
}

usb_names()     { perl -e 'alarm 15; exec @ARGV' ioreg -p IOUSB -l -w0 | grep -oE '"USB Product Name" = "[^"]+"' | cut -d'"' -f4; }
pongo_present() { usb_names | grep -qx "PongoOS USB Device"; }
pongo_version() { ./loader/pongo-shell 2>/dev/null | grep -oE 'pongoOS [0-9.]+' | head -1; }

enter_pongo() {
  if pongo_present; then ok "pongoOS already running"; return; fi
  step "Step 1/4: checkm8 exploit via palera1n"
  cat <<'EOF'
  1. palera1n will put the phone into Recovery itself
  2. When "Press Enter when ready for DFU mode" appears, press Enter
  3. Press the buttons EXACTLY ON THE ON-SCREEN COUNTDOWN:
       side + volume-down -> then release side, keep holding volume-down
  If it hangs on "reconnect in download mode", unplug and replug the cable.
EOF
  while true; do
    "$PALERA1N" -p && break
    warn "palera1n failed. Replug the cable if needed and press Enter to retry (Ctrl+C to quit)"
    read -r
  done
  printf 'waiting for pongoOS'
  for _ in $(seq 1 60); do pongo_present && break; printf '.'; sleep 1; done
  echo
  pongo_present || fail "pongoOS did not appear on USB"
  sleep 3
  ok "pongoOS running"
}

chainload_pongo() {
  step "Step 2/4: loading PongoOS 2.6.1 (with Linux support)"
  local ver; ver=$(pongo_version)
  if [ "$ver" = "pongoOS 2.6.1" ]; then ok "already 2.6.1"; return; fi
  ./loader/pongo-bootr pongo-rel/Pongo-2.6.1.bin >/dev/null 2>&1
  for _ in $(seq 1 30); do
    sleep 1
    [ "$(pongo_version)" = "pongoOS 2.6.1" ] && { ok "PongoOS 2.6.1 running"; return; }
  done
  fail "PongoOS 2.6.1 did not start (reboot the phone and try again)"
}

BASE_CMDLINE="earlycon=hx_uart,0x20a0c0000 console=tty0 console=ttyHX0 selinux=1 enforcing=0 androidboot.selinux=permissive printk.devkmsg=on androidboot.hardware=ranchu"

upload_kernel() { # img dtb [initrd]
  step "Step 3/4: uploading the kernel"
  local out cmdline="$BASE_CMDLINE"
  # NOREBOOT=1: on a fatal error the phone freezes with the log on screen instead of rebooting to iOS
  [ "${NOREBOOT:-0}" = 1 ] && { cmdline="$cmdline hx_reboot.noreboot=1"; warn "debug mode: on error the phone freezes with the log on screen -- photograph it"; }
  # QUIET=1: only kernel warnings/errors on the console (hides init's info spam, keeps stdio_to_kmsg/logcat errors)
  [ "${QUIET:-0}" = 1 ] && cmdline="$cmdline loglevel=5"
  [ -n "${EXTRA_CMDLINE:-}" ] && cmdline="$cmdline $EXTRA_CMDLINE"
  # persistent /data (Android 16): nonce of userdata.img and, once known, its header block
  if [ "$SYSTEM" = a16 ] && [ -n "$UD_NONCE" ]; then cmdline="$cmdline androidboot.sc_userdata=$UD_NONCE${UD_HDR:+:$UD_HDR}"; fi
  if [ -n "${3:-}" ]; then out=$(INITRD="$3" ./loader/pongo-linux "$1" "$2" "$cmdline" 2>&1)
  else out=$(./loader/pongo-linux "$1" "$2" "$cmdline" 2>&1); fi
  echo "$out" | grep -q "boot command sent" || { echo "$out"; fail "failed to upload the kernel"; }
  ok "kernel booted"
}

wait_android() {
  step "Step 4/4: waiting for Android to boot (1-3 min)"
  adb start-server >/dev/null 2>&1
  local t=0
  until adb devices 2>/dev/null | grep -q 'device$'; do
    sleep 2; t=$((t+2)); printf '.'
    if [ $t -ge 240 ]; then
      echo
      if usb_names | grep -qiE '^iPhone$|Recovery|DFU'; then
        fail "the phone returned to iOS (Android crashed). Just run ./android.sh again"
      fi
      fail "ADB did not appear within 4 minutes"
    fi
  done
  echo; ok "ADB connected"
  ensure_root
  t=0
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 2; t=$((t+2)); printf '.'
    [ $t -ge 300 ] && { echo; warn "boot not confirmed, tuning anyway"; break; }
  done
  echo; ok "Android booted"
}

tune() {
  step "Tuning performance"
  ensure_root
  # RES: render resolution. No GPU — SwiftShader draws every frame on 2 CPU cores, so fewer pixels = smoother.
  # Measured on A16 (median frame): 750x1334 ~150 ms, 562x1000 81 ms, 450x800 48 ms, 375x667 42 ms.
  local res=${RES:-450x800} dens=${DENSITY:-196}
  # Heat: kernel has no CPU_THERMAL (41.8 °C seen at full speed; a fixed 1056000 cap halved UI speed).
  # sc-thermal.sh runs full speed and steps the cap down from 41 °C battery temp (see patch-vulkan/sc-thermal.sh).
  # Rendering: sc-render.sh — HWUI on A10 GLES, app GL through ANGLE on our SwiftShader Vulkan (WebView works),
  # SystemUI/launcher native (the shade flickered). RENDER=angle|gl|vk → persist.sc.render (vk = fastest start, Aurora flickers).
  # Both scripts live in /system/bin after the patch-vulkan deploy; until then they are pushed to /data/local/tmp.
  local render=${RENDER:-$(adb shell getprop persist.sc.render 2>/dev/null | tr -d '\r')}
  render=${render:-angle}
  local s
  for s in sc-render.sh sc-thermal.sh; do
    adb shell "[ -x /system/bin/$s ]" 2>/dev/null || adb push "patch-vulkan/$s" "/data/local/tmp/$s" >/dev/null 2>&1
  done
  adb shell "
    sleep 10  # let sc-sandcastle.rc's boot_completed actions run first (old v1 rc sets all_angle=1)
    setprop persist.sc.render $render
    for c in /sys/devices/system/cpu/cpu*/cpufreq; do echo schedutil > \$c/scaling_governor; done
    bin=/system/bin; [ -x \$bin/sc-render.sh ] || bin=/data/local/tmp
    if [ \"\$(getprop ro.hardware.vulkan)\" = pastel ]; then
      restart=0
      [ $render != vk ] && { [ \"\$(getprop debug.hwui.renderer)\" = skiavk ] || [ \"\$(settings get global angle_gl_driver_all_angle)\" = 1 ]; } && restart=1
      sh \$bin/sc-render.sh
      [ \$restart = 1 ] && kill \$(pidof com.android.systemui) \$(pidof com.android.launcher3) \$(pidof \$(settings get secure default_input_method | cut -d/ -f1))
    fi
    ps -A -o ARGS | grep -q '[s]c-thermal.sh' || { chmod 755 \$bin/sc-thermal.sh; nohup setsid sh \$bin/sc-thermal.sh </dev/null >/dev/null 2>&1 & }
    # WebView provider is not auto-selected on this GSI (apps then have no WebView at all).
    cmd webviewupdate set-webview-implementation com.android.webview
    settings put secure doze_enabled 0
    # App installs crashed the phone (Gboard 95 MB, dex2oat on 2 GB RAM): verify-only install compile, 1 thread, capped heap.
    setprop pm.dexopt.install verify; setprop pm.dexopt.install-fast verify
    setprop dalvik.vm.dex2oat-threads 1; setprop dalvik.vm.dex2oat-Xmx 256m; setprop dalvik.vm.dex2oat-Xms 64m
    # 2 GB RAM, /data in tmpfs, no swap → kswapd thrash. zram swap (kernel has no lz4 backend, use lzo-rle).
    if ! grep -q zram0 /proc/swaps; then
      echo 1 > /sys/block/zram0/reset
      echo lzo-rle > /sys/block/zram0/comp_algorithm
      echo 1258291200 > /sys/block/zram0/disksize && mkswap /dev/block/zram0 && swapon /dev/block/zram0
    fi
    echo 100 > /proc/sys/vm/swappiness
    stop sc_kmsglog
    wm size $res
    wm density $dens
    settings put global window_animation_scale 0.5
    settings put global transition_animation_scale 0.5
    settings put global animator_duration_scale 0.5
    settings put global stay_on_while_plugged_in 0
    settings put system screen_off_timeout 300000
    dmesg -n 1
  " >/dev/null 2>&1
  local swap; swap=$(adb shell "grep -c zram0 /proc/swaps" 2>/dev/null | tr -d '\r')
  ok "resolution $res, zram-swap: $([ "$swap" = 1 ] && echo on || echo NO), animations x0.5, screen off after 5 min, thermal guard on, render $render"
}

# /data lives in RAM (tmpfs) because the kernel mounts APFS read-only, so Android forgets
# everything on reboot. We keep a copy of /data on the Mac and put it back after boot.
# Saved data only fits the Android it came from: SYSTEM=a16 keeps a separate archive.
DATA_TAR=data/userdata-$SYSTEM.tar
DATA_DIRS="app app-lib data user_de system system_ce system_de misc/wifi misc_ce misc_de media dalvik-cache"

save_data() {
  step "Saving Android data to the Mac"
  ensure_root
  use_wifi_adb
  mkdir -p data
  adb shell sync >/dev/null 2>&1
  local dirs; dirs=$(adb shell "cd /data && for d in $DATA_DIRS; do [ -e \$d ] && echo \$d; done" | tr -d '\r' | tr '\n' ' ')
  echo "  packing /data on the phone (~20-40 s)..."
  # tar exits non-zero on the sockets under /data (harmless), so judge by the archive itself
  t 180 adb shell "rm -f /data/local/tmp/userdata.tar; cd /data && tar -cf /data/local/tmp/userdata.tar $dirs >/dev/null 2>&1; true" >/dev/null 2>&1
  local packed; packed=$(t 20 adb shell stat -c %s /data/local/tmp/userdata.tar 2>/dev/null | tr -d '\r')
  [ "${packed:-0}" -gt 1000000 ] || fail "failed to pack /data on the phone"
  echo "  packed, transferring to the Mac"
  pull_file /data/local/tmp/userdata.tar "$DATA_TAR.tmp" || fail "failed to copy /data"
  adb shell rm -f /data/local/tmp/userdata.tar
  local size; size=$(stat -f %z "$DATA_TAR.tmp")
  [ "$size" -gt 1000000 ] || { rm -f "$DATA_TAR.tmp"; fail "archive suspiciously small ($size bytes), keeping the old copy"; }
  [ -f "$DATA_TAR" ] && mv -f "$DATA_TAR" "$DATA_TAR.prev"
  mv "$DATA_TAR.tmp" "$DATA_TAR"
  ok "saved: $DATA_TAR ($((size / 1048576)) MB). Previous copy: $DATA_TAR.prev"
}

restore_data() {
  [ -f "$DATA_TAR" ] || { warn "no saved data -- clean Android (to save: ./android.sh save)"; return; }
  step "Restoring saved data ($(( $(stat -f %z "$DATA_TAR") / 1048576 )) MB)"
  ensure_root
  # Mac→phone is reliable even over the flaky USB gadget; phone→Mac is not (see save_data).
  echo "  transferring the archive to the phone"
  push_file "$DATA_TAR" /data/local/tmp/userdata.tar || fail "failed to transfer the archive (Android untouched)"
  # Unpack from a detached script on the phone: an ADB drop must not kill it halfway
  # (that leaves the framework stopped and the screen black).
  echo "  unpacking on the phone and restarting the UI (~1 min, screen will go dark)"
  t 20 adb shell 'cat > /data/local/tmp/restore.sh <<"EOS"
stop
sleep 3
cd /data
tar -xf /data/local/tmp/userdata.tar > /data/local/tmp/restore.log 2>&1
restorecon -R /data/app /data/data /data/user_de /data/system /data/system_ce /data/system_de /data/misc/wifi /data/media >> /data/local/tmp/restore.log 2>&1
rm -f /data/local/tmp/userdata.tar
start
echo done >> /data/local/tmp/restore.log
EOS
chmod 755 /data/local/tmp/restore.sh; rm -f /data/local/tmp/restore.log; nohup setsid sh /data/local/tmp/restore.sh >/dev/null 2>&1 </dev/null &' >/dev/null 2>&1
  local waited=0
  until [ "$(t 10 adb shell tail -1 /data/local/tmp/restore.log 2>/dev/null | tr -d '\r')" = "done" ]; do
    sleep 5; waited=$((waited+5))
    [ $((waited % 15)) = 0 ] && echo "  unpacking... ${waited}s"
    [ $waited -ge 300 ] && fail "unpacking did not finish within 5 minutes"
    adb_ready >/dev/null 2>&1 || true
  done
  wait_framework
  ok "data restored"
}

# sys.boot_completed stays 1 across stop/start, so wait for the package manager to answer again.
wait_framework() {
  local waited=0
  sleep 8
  until t 15 adb shell pm path android 2>/dev/null | grep -q package:; do
    sleep 3; waited=$((waited+3))
    [ $((waited % 15)) = 0 ] && echo "  waiting for the Android UI... ${waited}s"
    if [ $waited -ge 240 ]; then warn "the Android UI did not respond within 4 minutes"; return 1; fi
    adb_ready >/dev/null 2>&1 || true
  done
}

# ---------- persistent /data for Android 16 ----------
# The kernel's APFS can't write files, so iOS creates /userdata.img on the Android volume with every 4K block
# tagged (nonce + index). Android (system/bin/sc-userdata.sh + scdata) finds those blocks on the raw disk,
# maps exactly them with device-mapper and formats ext4 there — APFS metadata and iOS data are never written.
UD_CONF=userdata-a16.conf
UD_NONCE=; UD_HDR=
[ -f "$UD_CONF" ] && . "./$UD_CONF"
save_ud_conf() { printf 'UD_NONCE=%s\nUD_HDR=%s\n' "$UD_NONCE" "$UD_HDR" > "$UD_CONF"; }

ensure_userdata_img() { # needs jailbroken iOS
  step "Android persistent storage: checking userdata.img"
  ios 'mkdir -p /var/mnt/android; mount | grep -q " /var/mnt/android " || for d in /dev/disk0s1s*; do [ "$(/System/Library/Filesystems/apfs.fs/apfs.util -p "$d" 2>/dev/null)" = Android ] && { mount -t apfs "$d" /var/mnt/android; break; }; done' || fail "the Android volume did not mount"
  local have; have=$(ios 'ls -ln /var/mnt/android/userdata.img 2>/dev/null' | awk '{print $5}')
  if [ -n "$have" ]; then
    [ -n "$UD_NONCE" ] || { warn "userdata.img exists but $UD_CONF is lost -- leaving the file alone, /data will be in RAM"; return; }
    ok "userdata.img already exists ($((have / 1073741824)) GB)"; return
  fi
  local free_gb; free_gb=$(ios 'df -k /var/mnt/android' | awk 'NR==2 {print int($4/1048576)}')
  local gb=${USERDATA_GB:-6}
  [ $((free_gb - 3)) -lt "$gb" ] && gb=$((free_gb - 3))
  if [ "$gb" -lt 2 ]; then warn "only ${free_gb} GB free on the iPhone -- too little for userdata.img, /data stays in RAM"; return; fi
  local nonce; nonce=$(openssl rand -hex 8)
  echo "  creating a ${gb} GB userdata.img (${free_gb} GB free; keeping at least 3 GB for iOS), ~3-8 min"
  python3 -c '
import sys, struct
nonce, total = int(sys.argv[1], 16), int(sys.argv[2]) * 262144
out = sys.stdout.buffer; pad = bytes(4064)
for i in range(total):
    out.write(b"SCUDATA1" + struct.pack("<QQQ", nonce, i, total) + pad)
' "$nonce" "$gb" | "$SSHPASS_BIN" -p "$IOS_SSH_PASS" ssh -C -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o PubkeyAuthentication=no -o LogLevel=ERROR root@$IOS_IP 'cat > /var/mnt/android/userdata.img.part && sync' \
    || { ios 'rm -f /var/mnt/android/userdata.img.part'; fail "userdata.img transfer interrupted"; }
  have=$(ios 'ls -ln /var/mnt/android/userdata.img.part' | awk '{print $5}')
  [ "$have" = $((gb * 1073741824)) ] || { ios 'rm -f /var/mnt/android/userdata.img.part'; fail "userdata.img has the wrong size ($have)"; }
  ios 'cd /var/mnt/android && mv userdata.img.part userdata.img && sync' || fail "failed to rename userdata.img"
  UD_NONCE=$nonce; UD_HDR=; save_ud_conf
  ok "userdata.img created; on first boot Android will locate its blocks (~1.5 min longer than usual)"
  ios 'sync; cd / && umount /var/mnt/android' >/dev/null 2>&1 || true
}

# after boot: remember the header block (next boots skip the scan) and tell whether /data is persistent
userdata_status() {
  [ "$SYSTEM" = a16 ] && [ -n "$UD_NONCE" ] || return 1
  local hdr mounted
  hdr=$(adb shell getprop sc.userdata.hdr 2>/dev/null | tr -d '\r')
  mounted=$(adb shell getprop sc.userdata.mounted 2>/dev/null | tr -d '\r')
  if [ -n "$hdr" ] && [ "$hdr" != "$UD_HDR" ]; then UD_HDR=$hdr; save_ud_conf; fi
  if [ "$mounted" = 1 ]; then ok "Android persistent storage mounted -- data is saved automatically"; return 0; fi
  warn "persistent storage did not mount (details: adb shell dmesg | grep sc-userdata), /data in RAM"
  return 1
}

# APKs dropped into apks/ are installed after boot when missing (e.g. after a wipe or while /data is still in RAM)
install_apks() {
  local apk pkg
  for apk in apks/*.apk; do
    [ -f "$apk" ] || continue
    case "$apk" in *F-Droid*) pkg=org.fdroid.fdroid ;; *) pkg= ;; esac
    if [ -n "$pkg" ] && adb shell pm path "$pkg" 2>/dev/null | grep -q package:; then continue; fi
    echo "  installing $(basename "$apk")"
    t 180 adb install -r "$apk" >/dev/null 2>&1 && ok "$(basename "$apk") installed" || warn "failed to install $(basename "$apk")"
  done
}

# ---------- deploy: push a rebuilt Android 16 nand through jailbroken iOS, then boot it ----------
# (IOS_IP is required only by deploy — it is checked in the deploy case, NOT here, so the
#  default `./android.sh` boot works fine with an empty IOS_IP.)
ios() { t "${IOS_TIMEOUT:-30}" "$SSHPASS_BIN" -p "$IOS_SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o PubkeyAuthentication=no -o LogLevel=ERROR -o ConnectTimeout=6 root@$IOS_IP "$@"; }

ensure_jailbroken_ios() {
  if IOS_TIMEOUT=10 ios true 2>/dev/null; then ok "jailbroken iOS already running"; return; fi
  step "Stage 1/3: booting jailbroken iOS (palera1n -f)"
  cat <<'EOT'
  DFU buttons #1 of 2 -- as usual: Enter, then exactly on the on-screen countdown.
  If it hangs on "reconnect in download mode", unplug and replug the cable.
EOT
  while true; do
    "$PALERA1N" -f && break
    warn "palera1n failed. Replug the cable and press Enter to retry (Ctrl+C to quit)"; read -r
  done
  printf '  waiting for iOS to boot and join Wi-Fi'
  local waited=0
  until IOS_TIMEOUT=10 ios true 2>/dev/null; do
    sleep 5; waited=$((waited+5)); printf '.'
    [ $waited -ge 420 ] && { echo; fail "iOS did not appear on the network within 7 minutes (is the phone on Wi-Fi?)"; }
  done
  echo; ok "jailbroken iOS online"
}

deploy_nand() { # local-nand local-sha-file
  step "Stage 2/3: updating Android 16 on the phone"
  local want; want=$(cut -d' ' -f1 "$2")
  ios 'mkdir -p /var/mnt/android; mount | grep -q " /var/mnt/android " || for d in /dev/disk0s1s*; do [ "$(/System/Library/Filesystems/apfs.fs/apfs.util -p "$d" 2>/dev/null)" = Android ] && { mount -t apfs "$d" /var/mnt/android; break; }; done' || fail "the Android volume did not mount"
  local have; have=$(ios 'cat /var/mnt/android/nand.sha256 2>/dev/null' | tr -d '\r\n ')
  if [ -z "$have" ]; then
    echo "  no version marker on the phone -- computing the checksum (~1 min)"
    have=$(IOS_TIMEOUT=300 ios '{ sha256sum /var/mnt/android/nand 2>/dev/null || shasum -a 256 /var/mnt/android/nand 2>/dev/null; }' | cut -d' ' -f1)
  fi
  if [ "$have" = "$want" ]; then
    ok "the phone already has this version -- no upload needed"
  else
    echo "  uploading $(basename "$1") (3.1 GB, usually 1-3 min)..."
    local start=$(date +%s)
    "$SSHPASS_BIN" -p "$IOS_SSH_PASS" ssh -C -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no \
      -o LogLevel=ERROR root@$IOS_IP 'cat > /var/mnt/android/nand.part && sync' < "$1" || fail "transfer interrupted (the old version on the phone is untouched)"
    echo "  transferred in $(( $(date +%s) - start )) s, verifying the checksum (~1 min)"
    local got; got=$(IOS_TIMEOUT=300 ios '{ sha256sum /var/mnt/android/nand.part 2>/dev/null || shasum -a 256 /var/mnt/android/nand.part; }' | cut -d' ' -f1)
    [ "$got" = "$want" ] || fail "checksum mismatch (the old version on the phone is untouched)"
    ios "cd /var/mnt/android && mv -f nand.part nand && echo $want > nand.sha256 && sync" || fail "failed to replace nand"
    ok "Android 16 on the phone updated and verified"
  fi
  ios 'sync; cd / && umount /var/mnt/android' >/dev/null 2>&1 || true
}

reboot_ios_to_recovery() {
  step "Stage 3/3: putting the phone into Recovery (no buttons)"
  IOS_TIMEOUT=15 ios 'nvram auto-boot=false; sync; (sleep 1; reboot) >/dev/null 2>&1 &' >/dev/null 2>&1 || true
  printf '  waiting for Recovery'
  local waited=0
  until usb_names | grep -q 'Recovery'; do
    sleep 3; waited=$((waited+3)); printf '.'
    [ $waited -ge 150 ] && { echo; warn "Recovery did not appear within 2.5 min -- palera1n will switch the phone itself"; return; }
  done
  echo; ok "phone in Recovery"
}

# A stale adb server can wedge the macOS USB stack once the Android gadget disappears (needed a Mac reboot).
case "${1:-android}" in android|linux|deploy) perl -e 'alarm 10; exec @ARGV' adb kill-server >/dev/null 2>&1 ;; esac

case "${1:-android}" in
  android)
    enter_pongo; chainload_pongo
    upload_kernel "$ANDROID_IMG" "$ANDROID_DTB" "$ANDROID_INITRD"
    wait_android
    if userdata_status; then tune; install_apks; bold ""; bold "🤖 Android is ready. Data is saved on the phone automatically."
    else restore_data; tune; install_apks; bold ""; bold "🤖 Android is ready. Before shutdown, save your data: ./android.sh save"; fi
    ;;
  save)
    adb devices | grep -q 'device$' || fail "Android is not connected over ADB"
    save_data
    perl -e 'alarm 10; exec @ARGV' adb kill-server >/dev/null 2>&1
    ok "ADB stopped -- you can power off the phone"
    ;;
  restore)
    adb devices | grep -q 'device$' || fail "Android is not connected over ADB"
    restore_data; tune
    ;;
  tune)
    adb devices | grep -q 'device$' || fail "Android is not connected over ADB"
    tune
    ;;
  deploy)
    # one command for the Android 16 test loop: jailbroken iOS → upload nand if changed → Recovery → boot A16
    export SYSTEM=a16
    ANDROID_IMG=${KERNEL:-work/Image-a16f.lzma}
    NOREBOOT=${NOREBOOT:-0}
    QUIET=${QUIET:-1}
    NAND=${NAND:-nand-a16}
    [ -f "$NAND" ] && [ -f "$NAND.sha256" ] || fail "missing $NAND or $NAND.sha256"
    [ -n "$IOS_IP" ] || fail "IOS_IP is not set — copy config.env.example to config.env and set your iPhone's IP (needed for deploy)"
    ensure_jailbroken_ios
    deploy_nand "$NAND" "$NAND.sha256"
    ensure_userdata_img
    reboot_ios_to_recovery
    step "Booting Android 16 -- DFU buttons #2 of 2"
    enter_pongo; chainload_pongo
    upload_kernel "$ANDROID_IMG" "$ANDROID_DTB" "$ANDROID_INITRD"
    wait_android && { userdata_status; tune; install_apks; }
    bold ""
    bold "🤖 Android 16 is ready. Next boots: ./android.sh (no nand upload)."
    warn "deploy left the phone set to stay in Recovery between boots (needed for tethered boot)."
    bold "   To use normal iOS again, run:  ~/.local/bin/palera1n -n   — do NOT 'Restore' in Finder (that erases it)."
    ;;
  linux)
    enter_pongo; chainload_pongo
    upload_kernel "$LINUX_IMG" "$LINUX_DTB"
    bold "🐧 Linux is booting. For SSH: sudo ifconfig en6 172.16.1.2 netmask 255.255.255.0 up && ssh root@172.16.1.1 (password alpine)"
    ;;
  *) echo "usage: $0 [android|deploy|save|restore|tune|linux]"; exit 1 ;;
esac
