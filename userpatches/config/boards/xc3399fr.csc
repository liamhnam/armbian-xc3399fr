# Rockchip RK3399 hexa core 4GB LPDDR4 eMMC GBE 2x USB3 HDMI WiFi/BT
#
# Product build for Xiangcheng XC3399FR v1.1a (proembed.com).
# Upstream submission: https://github.com/armbian/build/pull/10619
#
# This file intentionally stays as close as possible to the upstream board
# config. The only addition is the watchdog hook at the bottom, which exists
# because these units are sold as always-on NAS / Docker / home-server boxes
# that must recover from a kernel hang unattended. Anything that is not specific
# to that product belongs upstream, not here.
BOARD_NAME="XC3399FR"
BOARD_VENDOR="proembed"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="liamhnam"
INTRODUCED="2021"
BOOTCONFIG="fine3399-rk3399_defconfig"
# Product images ship 'current' only, on purpose: customers get the LTS kernel
# the board was validated on. Upstream additionally offers edge/bleedingedge.
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3399-xc3399fr.dtb"
BOOT_SCENARIO="only-blobs"

# Deliberately no SRC_EXTLINUX here, unlike fine3399 which this device tree was
# derived from. boot.scr + armbianEnv.txt is what makes the stock
# armbian-install "boot from eMMC, system on this disk" flow work on this
# board: the rockchip64 boot script resolves every path through ${prefix}, so
# one script boots whether /boot is a directory (SD) or its own partition
# (eMMC). Worth revisiting once armbian/configng#985 is merged.

# NOTE ON usbstoragequirks - deliberately NOT set here.
#
# An earlier revision pinned the OWC 7825:a2a4 USB-SATA bridge to BOT, because
# that bridge has a genuinely broken UAS implementation (docs/storage.md §6:
# over 20 warm reboots on two different cables, 7 stalled ~30 s and one never
# brought the disk up at all, needing a power cycle).
#
# That line is gone because units no longer ship with that cable. Hardcoding a
# VID:PID quirk for a device the customer probably does not own would only
# penalise everyone whose bridge is fine - BOT costs 4-11x random IOPS.
#
# Leaving the variable unset is also what keeps Armbian's own UAS blacklist
# working: armbian-hardware-optimization installs its Norelsys NS1066/NS1068
# entries ONLY when usbstoragequirks is EMPTY. Writing any value of our own
# would silently replace that list rather than add to it.
#
# Net effect: these images behave exactly like stock Armbian. A good bridge runs
# UAS at full speed; a known-bad Norelsys is blacklisted by Armbian; anything
# else behaves as it would on any other distro, and docs/storage.md tells the
# user how to diagnose it and how to flip transports with
# tools/board/storage-transport.sh.

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

# NOTE ON smartd - deliberately NOT configured here.
#
# A revision of this file shipped a smartd.conf with `DEVICESCAN -d sat`, on the
# reasoning that smartd cannot probe a disk behind a USB-SATA bridge without
# being told the transport. Testing on hardware showed that config does not
# work either:
#
#   DEVICESCAN -a        -> "NO devices found to scan"          (exit 17)
#   DEVICESCAN -d sat    -> "/dev/sda open() failed: Not a SAT device" (exit 17)
#   /dev/sda -d sat      -> "[SAT], is SMART capable"           (exit 0)
#
# Only an explicit device entry works, and hardcoding /dev/sda is wrong here
# because disk letters are not stable across boots on this board. Note also
# that eMMC and SD cards do not implement SMART at all, so on a unit without a
# USB disk there is nothing for smartd to monitor and it exits 17 - a red
# FAILED unit for no reason.
#
# A config that silently monitors nothing is worse than no config, so the image
# ships none. docs/install.md documents the two lines needed to enable it on a
# unit that actually has a USB-attached SATA disk.
