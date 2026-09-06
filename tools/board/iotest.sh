#!/bin/bash
# Quick storage sanity check for a unit in the field.
#
# SETTLE is the whole point of this script's shape. Reading a file back
# immediately after writing 1.5 GB measures a drive that is still flushing and
# garbage-collecting, not the drive's read speed. This trap has been fallen
# into during this project's own bring-up: a sequential read measured 61 MB/s
# five seconds after heavy random writes and 212-339 MB/s once the drive had
# settled for 60 s. Same drive, same command, 4x apart.
#
# Override for a faster (less accurate) run:  SETTLE=10 ./iotest.sh
SETTLE="${SETTLE:-60}"
LOOPS="${LOOPS:-3}"
SIZE_MB="${SIZE_MB:-1500}"
DIR="${DIR:-/root}"

echo "=== Che do truyen ==="
if dmesg | grep -q "scsi host0: uas"; then echo "UAS"; else echo "BOT (usb-storage)"; fi

echo "=== Cong USB dang dung ==="
src=$(findmnt -n -o SOURCE / | sed 's|/dev/||; s|[0-9]*$||')
readlink -f "/sys/class/block/${src}/device" 2>/dev/null | grep -oE 'fe[89]00000\.usb' || echo "(khong phai USB)"

echo "=== ${LOOPS} vong ghi ${SIZE_MB}MB, nghi ${SETTLE}s, roi doc lai ==="
for i in $(seq 1 "$LOOPS"); do
	dd if=/dev/zero of="$DIR/tf.$i" bs=1M count="$SIZE_MB" conv=fsync 2>&1 | tail -1
	sync
	echo "  ... nghi ${SETTLE}s cho o on dinh truoc khi do toc do doc"
	sleep "$SETTLE"
	dd if="$DIR/tf.$i" of=/dev/null bs=1M iflag=direct 2>&1 | tail -1
	rm -f "$DIR/tf.$i"
done

echo "=== Loi (0 la tot) ==="
dmesg | grep -icE 'uas_eh|usb .*reset|I/O error|EXT4-fs error|read-only'

echo "=== Filesystem ==="
findmnt -n -o SOURCE,OPTIONS /
