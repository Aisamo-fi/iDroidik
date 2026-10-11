#!/bin/bash
# Put the SwiftShader Vulkan driver + rc changes into nand-a16 (on the Mac), then deploy with ./android.sh deploy.
# Re-running updates only files that differ from patch-vulkan/. Backup of the pre-Vulkan image: nand-a16.bak-pre-vulkan.
# Undo everything: cp -c nand-a16.bak-pre-vulkan nand-a16 && shasum -a 256 nand-a16 > nand-a16.sha256
set -euo pipefail
cd "$(dirname "$0")/.."
P=$PWD/patch-vulkan N=$PWD/nand-a16
VEND_OFF=3145728    VEND_LEN=201326592     # super sectors [2048..395264)
SYS_OFF=204472320   SYS_LEN=2935996800     # super sectors [395264..6129664)

colima status >/dev/null 2>&1 || { echo "starting colima..."; colima start; }

[ -f nand-a16.bak-pre-vulkan ] || cp -c nand-a16 nand-a16.bak-pre-vulkan
[ "$(shasum -a 256 nand-a16 | cut -d' ' -f1)" = "$(cut -d' ' -f1 nand-a16.sha256)" ] || { echo "nand-a16 does not match nand-a16.sha256 -- changed without updating the sum? stop"; exit 1; }

printf 'u:object_r:same_process_hal_file:s0\0' > "$P/ea_hal"
printf 'u:object_r:system_file:s0\0' > "$P/ea_sys"

# part fs-offset fs-len image-path local-file mode gid selinux-label-file
FILES="
V $VEND_OFF $VEND_LEN /lib64/hw/vulkan.pastel.so vulkan.pastel.so 0100644 0 ea_hal
S $SYS_OFF $SYS_LEN /system/bin/sc-render.sh sc-render.sh 0100755 2000 ea_sys
S $SYS_OFF $SYS_LEN /system/bin/sc-thermal.sh sc-thermal.sh 0100755 2000 ea_sys
S $SYS_OFF $SYS_LEN /system/etc/init/sc-sandcastle.rc sc-sandcastle.rc 0100644 0 ea_sys
"

colima ssh -- sh -s <<EOF
set -e
V=\$(sudo losetup -f --show -o $VEND_OFF --sizelimit $VEND_LEN $N)
S=\$(sudo losetup -f --show -o $SYS_OFF --sizelimit $SYS_LEN $N 2>/dev/null)
changed=0
echo "$FILES" | while read part off len path file mode gid ea; do
  [ -n "\$part" ] || continue
  dev=\$V; [ \$part = S ] && dev=\$S
  sudo rm -f /tmp/chk
  sudo debugfs -R "dump \$path /tmp/chk" \$dev 2>/dev/null
  if cmp -s /tmp/chk $P/\$file; then echo "  unchanged: \$path"; continue; fi
  echo "  writing: \$path"
  dir=\${path%/*}; name=\${path##*/}
  printf 'cd %s\nrm %s\nwrite %s %s\nsif %s mode %s\nsif %s gid %s\nea_set -f %s %s security.selinux\n' \
    "\$dir" "\$name" "$P/\$file" "\$name" "\$path" "\$mode" "\$path" "\$gid" "$P/\$ea" "\$path" > /tmp/cmd
  sudo debugfs -w -f /tmp/cmd \$dev >/dev/null 2>&1
  sync
  sudo rm -f /tmp/chk; sudo debugfs -R "dump \$path /tmp/chk" \$dev 2>/dev/null
  cmp /tmp/chk $P/\$file && echo "    verified"
done
echo "== fsck"
sudo e2fsck -fn \$V | tail -1
sudo e2fsck -fn \$S | tail -1
sudo rm -f /tmp/chk /tmp/cmd
sudo losetup -d \$V \$S
EOF

shasum -a 256 nand-a16 > nand-a16.sha256
echo "✅ nand-a16: $(cut -c1-8 nand-a16.sha256)…  If the sum changed -- run ./android.sh deploy"
