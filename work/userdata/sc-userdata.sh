#!/system/bin/sh
# Sandcastle: persistent /data on /efs/userdata.img without APFS writes (see scdata).
# ro.boot.sc_userdata=<nonce-hex>[:<header-block>]; without the block, scdata scans the container once (~80 s, read-only).
log() { echo "sc-userdata: $*" > /dev/kmsg; }
v=$(getprop ro.boot.sc_userdata)
[ -n "$v" ] || exit 0
nonce=${v%%:*}; hdr=; case "$v" in *:*) hdr=${v#*:} ;; esac
if [ -z "$hdr" ]; then
  blocks=$(( $(cat /sys/class/block/nvme0n1p1/size) / 8 ))
  log "no header block given, scanning $blocks blocks"
  hdr=$(/system/bin/scdata scan "$nonce" "$blocks" 2>/dev/kmsg) || { log "scan failed, /data stays tmpfs"; exit 0; }
fi
setprop sc.userdata.hdr "$hdr"
# nvme0n1p1 is claimed by the APFS mount, so device-mapper goes through a loop device
loopdev=$(losetup -f) && losetup "$loopdev" /dev/block/nvme0n1p1 || { log "losetup failed"; exit 0; }
table=$(SCDATA_DEV=$loopdev /system/bin/scdata attach "$nonce" "$hdr" 2>/dev/kmsg) || { log "attach refused, /data stays tmpfs"; losetup -d "$loopdev"; exit 0; }
dmctl create sc_userdata $table >/dev/null || { log "dmctl failed"; losetup -d "$loopdev"; exit 0; }
dev=$(dmctl getpath sc_userdata)
magic=$(dd if="$dev" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
if [ "$magic" != "53ef" ]; then
  log "formatting new ext4 on $dev"
  mke2fs -t ext4 -I 256 -L sc_userdata -q "$dev" 2>/dev/kmsg || { log "mke2fs failed"; exit 0; }
  setprop sc.userdata.fresh 1
else
  e2fsck -p "$dev" > /dev/kmsg 2>&1
fi
mount -t ext4 -o noatime,nosuid,nodev "$dev" /data || { log "mount failed, /data stays tmpfs"; exit 0; }
chmod 0771 /data; chown system:system /data
setprop sc.userdata.mounted 1
log "persistent /data mounted from $dev"
