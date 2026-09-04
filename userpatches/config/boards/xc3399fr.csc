# Xiangcheng XC3399FR v1.1a (proembed.com) - RK3399 hexa core 4GB LPDDR4, GbE, eMMC, 2x USB3
BOARD_NAME="XC3399FR v1.1a"
BOARD_VENDOR="proembed"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
INTRODUCED="26.2"
BOOTCONFIG="fine3399-rk3399_defconfig"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-xc3399fr.dtb"
BOOT_SCENARIO="only-blobs"

# Deliberately NOT SRC_EXTLINUX="yes".
#
# fine3399 - which this board config was derived from - is one of only 22 of
# Armbian's 362 boards that boot via extlinux. That matters for a board meant to
# run its rootfs on a USB SSD, because armbian-config's installer
# (install_run_split / install_rewrite_bootenv) only ever rewrites
# armbianEnv.txt; it has no extlinux support at all, in 26.8.0-trunk.426 or in
# the newer .0829 build. With extlinux the officially supported
# "Boot from eMMC, system on this disk" flow completes with exit 0 but leaves
# two broken things behind:
#
#   1. root= still points at the *source* device, and
#   2. extlinux.conf keeps its "/boot/..." path prefixes even though the eMMC
#      boot partition IS /boot, so u-boot cannot find the initrd, skips the
#      entry, falls through to EFI then PXE, and loops forever - the classic
#      "stops after U-Boot, SSD LED never lights" symptom.
#
# boot.scr has neither problem. The rockchip64 boot script addresses every file
# through ${prefix}, and u-boot sets that from boot_prefixes="/ /boot/" for
# whichever layout it actually finds, so the same boot.scr works whether /boot
# is a directory in the rootfs or a partition of its own. It also always appends
# rootwait (required: the USB SSD needs ~5 s to enumerate) and exposes
# usb-storage.quirks as a first-class armbianEnv.txt variable.
#
# Net effect: the customer runs armbian-install, picks the SSD, picks
# "Boot from eMMC, system on this disk", and it just works - with a completely
# stock armbian-config.

function image_specific_armbian_env_ready__xc3399fr_usb_quirks() {
	# This is the hook the build framework documents for exactly this: it only
	# runs when SRC_EXTLINUX != yes and guarantees armbianEnv.txt exists.
	display_alert "$BOARD" "adding board defaults to armbianEnv.txt" "info"

	# The ULT-Best/OWC 7825:a2a4 USB-SATA bridge has a broken UAS
	# implementation: without this quirk it throws uas_eh_abort_handler and
	# resets the device on roughly 40% of boots. Forcing usb-storage (BOT)
	# costs some write throughput and cures it completely. Remove this line
	# if the unit ships with a bridge that has sane UAS.
	echo "usbstoragequirks=7825:a2a4:u" >> "${SDCARD}"/boot/armbianEnv.txt

	cat "${SDCARD}"/boot/armbianEnv.txt
}

function post_family_tweaks__xc3399fr_watchdog() {
	# The RK3399 has a Synopsys DesignWare watchdog and the kernel exposes it
	# as /dev/watchdog0, but nothing feeds it by default, so a kernel hang on
	# an unattended 24/7 unit is never recovered. Hand it to systemd.
	display_alert "$BOARD" "enabling the hardware watchdog for 24/7 operation" "info"
	mkdir -p "${SDCARD}"/etc/systemd/system.conf.d
	cat <<- WATCHDOG > "${SDCARD}"/etc/systemd/system.conf.d/10-xc3399fr-watchdog.conf
		[Manager]
		RuntimeWatchdogSec=30s
		RebootWatchdogSec=10min
	WATCHDOG
}
