# Xiangcheng XC3399FR v1.1a (proembed.com) - product overlay.
#
# The board itself lives upstream since armbian/build#10619 merged
# (2026-09-06, commit 66dbc7af). Armbian sources config/boards/xc3399fr.csc
# first and this file second, so everything not set here - BOARD_NAME,
# BOARDFAMILY, BOOTCONFIG, BOOT_FDT_FILE, the device tree, all of it - comes
# from upstream and stays in step with it automatically.
#
# Only what is true of the units we ship belongs below. Anything true of the
# board in general is a bug here and belongs in a PR to armbian/build.

# Product images ship 'current' only, on purpose: customers get the LTS kernel
# the board was validated on. Upstream offers edge/bleedingedge as well so
# testers can use them; we do not want a customer box tracking a moving kernel.
KERNEL_TARGET="current"

function post_family_tweaks__xc3399fr_watchdog() {
	# The RK3399 has a Synopsys DesignWare watchdog and the kernel exposes it
	# as /dev/watchdog0, but nothing feeds it by default, so a kernel hang on
	# an unattended 24/7 unit is never recovered. Hand it to systemd.
	#
	# No Armbian board sets RuntimeWatchdogSec, so this is not a convention
	# and deliberately did not go upstream - but it is right for a box sold as
	# an always-on NAS / Docker / home server.
	display_alert "$BOARD" "enabling the hardware watchdog for 24/7 operation" "info"
	mkdir -p "${SDCARD}"/etc/systemd/system.conf.d
	cat <<- WATCHDOG > "${SDCARD}"/etc/systemd/system.conf.d/10-xc3399fr-watchdog.conf
		[Manager]
		RuntimeWatchdogSec=30s
		RebootWatchdogSec=10min
	WATCHDOG
}

# NOTE ON usbstoragequirks - deliberately NOT set here.
#
# An earlier revision pinned the OWC 7825:a2a4 USB-SATA bridge to BOT, because
# that bridge has a genuinely broken UAS implementation (docs/storage.md: over
# 20 warm reboots on two different cables, 7 stalled ~30 s and one never
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
