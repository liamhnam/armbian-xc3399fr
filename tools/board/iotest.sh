#!/bin/bash
echo "=== Che do truyen ==="
if dmesg | grep -q "scsi host0: uas"; then echo "UAS"; else echo "BOT (usb-storage)"; fi
echo "=== 3 vong ghi 1.5GB + doc lai ==="
for i in 1 2 3; do
  dd if=/dev/zero of=/root/tf.$i bs=1M count=1500 conv=fsync 2>&1 | tail -1
  dd if=/root/tf.$i of=/dev/null bs=1M iflag=direct 2>&1 | tail -1
  rm -f /root/tf.$i
done
echo "=== Loi (0 la tot) ==="
dmesg | grep -icE 'uas_eh|usb .*reset|I/O error|EXT4-fs error|read-only'
echo "=== Filesystem ==="
findmnt -n -o SOURCE,OPTIONS /
