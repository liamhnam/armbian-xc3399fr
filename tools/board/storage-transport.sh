#!/bin/bash
# storage-transport.sh -- show or switch how the USB system disk is driven.
#
# Run on the board as root.
#
#   ./storage-transport.sh              show the current state
#   ./storage-transport.sh uas          use UAS   (queued, fast, product default)
#   ./storage-transport.sh bot          use BOT   (queue depth 1, slow, always boots)
#
# Takes effect on the next reboot. See docs/storage.md for why the product
# images ship UAS and what the trade-off actually costs.
set -euo pipefail

ENV_FILE=/boot/armbianEnv.txt
BRIDGE="0x7825:0xa2a4:u"
# Armbian's own UAS blacklist. armbian-hardware-optimization only installs this
# when usbstoragequirks is EMPTY, so once we write the variable ourselves we
# have to carry these entries or we silently drop Armbian's protection for
# Norelsys NS1066/NS1068 bridges.
ARMBIAN_DEFAULT="0x2537:0x1066:u,0x2537:0x1068:u"

show_state() {
	local qd mode disk
	disk=$(findmnt -n -o SOURCE / | sed 's|/dev/||; s|[0-9]*$||')
	qd=$(cat "/sys/block/$disk/device/queue_depth" 2>/dev/null || echo "?")
	mode=$(dmesg | grep -oE 'scsi host0: (uas|usb-storage)' | head -1 || true)
	echo "rootfs disk      : /dev/$disk"
	echo "transport        : ${mode:-unknown}"
	echo "queue_depth      : $qd   (1 = BOT, 30 = UAS)"
	echo "port             : $(readlink -f "/sys/class/block/$disk/device" | grep -oE 'fe[89]00000\.usb' || echo '?')"
	echo "armbianEnv       : $(grep '^usbstoragequirks' "$ENV_FILE" 2>/dev/null || echo '(unset - Armbian default applies)')"
	echo "cmdline          : $(tr ' ' '\n' < /proc/cmdline | grep '^usb-storage.quirks' || echo '(none)')"
	echo "boot-time aborts : $(dmesg | grep -c uas_eh_abort || true)"
}

set_quirks() {
	sed -i '/^usbstoragequirks/d' "$ENV_FILE"
	[ -n "$1" ] && echo "usbstoragequirks=$1" >> "$ENV_FILE"
	sync
	echo "Updated $ENV_FILE:"
	grep '^usbstoragequirks' "$ENV_FILE" || echo "  (unset)"
	echo "Reboot for this to take effect."
}

case "${1:-show}" in
	show)
		show_state
		;;
	uas)
		# Leave only Armbian's default list, which does not contain our bridge.
		set_quirks "$ARMBIAN_DEFAULT"
		;;
	bot)
		set_quirks "$ARMBIAN_DEFAULT,$BRIDGE"
		;;
	*)
		echo "usage: $0 [show|uas|bot]" >&2
		exit 1
		;;
esac
