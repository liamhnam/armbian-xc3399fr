#!/bin/bash
# armbian-install-extlinux-fixup.sh
#
# armbian-install --boot split-emmc leaves two things wrong on boards that use
# extlinux instead of armbianEnv.txt (XC3399FR is one):
#
#   1. install_rewrite_bootenv only ever touches armbianEnv.txt, so
#      extlinux.conf keeps pointing root= at the *source* device.
#   2. install_populate_boot copies /boot to the root of the new boot
#      partition, but leaves the "/boot/..." prefixes in extlinux.conf. On the
#      eMMC the boot partition IS /boot, so u-boot looks for /boot/uInitrd,
#      does not find it, skips the entry, falls through to EFI then PXE, and
#      loops forever. This is the "stops after U-Boot" symptom.
#
# Run this once after armbian-install, before the first boot from eMMC.
# Usage: fixup.sh <boot-partition> <root-partition>
#   e.g. fixup.sh /dev/mmcblk2p1 /dev/sdb1
set -e
BOOTPART="${1:?usage: fixup.sh <boot-part> <root-part>}"
ROOTPART="${2:?usage: fixup.sh <boot-part> <root-part>}"

MP=$(mktemp -d)
mount "$BOOTPART" "$MP"
CFG="$MP/extlinux/extlinux.conf"
[ -f "$CFG" ] || { echo "no $CFG - nothing to fix"; umount "$MP"; rmdir "$MP"; exit 1; }
cp "$CFG" "$CFG.bak"

ROOT_UUID=$(blkid -s UUID -o value "$ROOTPART")

sed -i -e "s|root=UUID=[0-9a-fA-F-]*|root=UUID=$ROOT_UUID|" \
       -e 's|^\([[:space:]]*kernel[[:space:]]\+\)/boot/|\1/|' \
       -e 's|^\([[:space:]]*initrd[[:space:]]\+\)/boot/|\1/|' \
       -e 's|^\([[:space:]]*fdt[[:space:]]\+\)/boot/|\1/|' "$CFG"

# rootwait: a USB rootfs needs several seconds to enumerate.
grep -q 'rootwait' "$CFG" || sed -i 's|\(root=UUID=[0-9a-fA-F-]*\)|\1 rootwait|' "$CFG"

echo "--- resulting extlinux.conf ---"
cat "$CFG"
echo "--- verifying every referenced file exists ---"
rc=0
grep -E '^[[:space:]]*(kernel|initrd|fdt)[[:space:]]' "$CFG" | while read -r key path; do
  if [ -e "$MP$path" ]; then echo "OK      $key $path"; else echo "MISSING $key $path"; rc=1; fi
done
grep -q "root=UUID=$ROOT_UUID" "$CFG" && echo "OK      root=UUID=$ROOT_UUID"
sync
umount "$MP"; rmdir "$MP"
exit $rc
