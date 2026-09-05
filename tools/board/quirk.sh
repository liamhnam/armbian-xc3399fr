#!/bin/bash
# Tat UAS cho cau USB-SATA 7825:a2a4 (ULT-Best) - ep ve che do BOT
set -e
Q='usb-storage.quirks=7825:a2a4:u'

mkdir -p /mnt/e
mountpoint -q /mnt/e || mount /dev/mmcblk2p1 /mnt/e

for f in /mnt/e/boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf; do
  if grep -q "$Q" "$f"; then
    echo "DA_CO_SAN: $f"
  else
    sed -i "s|rootwait|rootwait $Q|" "$f"
    echo "DA_THEM:   $f"
  fi
done

echo "--- KIEM TRA ---"
grep -o "$Q" /mnt/e/boot/extlinux/extlinux.conf | head -1
grep -o "$Q" /boot/extlinux/extlinux.conf | head -1
echo "--- DONG append tren eMMC ---"
grep append /mnt/e/boot/extlinux/extlinux.conf

sync
umount /mnt/e
echo XONG
