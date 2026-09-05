# Boot from eMMC, system on a USB SSD

The headline use-case for the XC3399FR v1.1a is: **bootloader and `/boot` on the
internal eMMC, root filesystem on a fast USB 3.0 SSD.** The RK3399 BootROM cannot
boot from USB, so U-Boot must live on the eMMC; the large/fast SSD then carries
everything else. This is the layout Armbian calls *split-emmc*.

## How to set it up (customer flow)

1. Flash the release image to a micro-SD card and boot the board from it.
2. Plug the SSD into the **`vcc5v0_host`** USB3 port (see the port warning in the
   [README](../README.md) — the other port cannot power a 2.5″ drive reliably).
3. Run the stock installer and follow the menu:
   ```bash
   sudo armbian-install
   ```
   - target: your USB SSD
   - mode: **Boot from eMMC, system on this disk (+ /emmc_storage)**
4. Power off, remove the SD card, power on.

Result:

```
/               → SSD partition   (ext4)
/boot           → eMMC partition 1 (ext4)   kernel, initrd, dtb, boot.scr
/emmc_storage   → eMMC partition 2 (ext4)   spare space, mounted nofail
```

No manual editing is required. That is the whole point of this port.

## Why the generic fine3399 config failed here

`fine3399` sets `SRC_EXTLINUX="yes"`. Only **22 of Armbian’s 362 boards** use
extlinux; the split-emmc installer was written for the other 340, which use
`boot.scr` + `armbianEnv.txt`. Two things broke:

1. **`armbian-install` never rewrote the root device.**
   `install_rewrite_bootenv` only edits `armbianEnv.txt`. With extlinux there is
   no such file, so `root=` in `extlinux.conf` kept pointing at the *source*
   (the SD card), not the new SSD.

2. **The `/boot/` path prefix was wrong on the eMMC.**
   The installer copies `/boot` to the root of the eMMC boot **partition**, but
   leaves `extlinux.conf` saying `kernel /boot/Image`. On the SD card `/boot` is
   a *directory inside the rootfs*, so `/boot/Image` is right. On the eMMC the
   boot partition **is** `/boot`, so the file is at `/Image` and U-Boot cannot
   find `/boot/uInitrd`:
   ```
   Found /extlinux/extlinux.conf
   Retrieving file: /boot/uInitrd
   ** File not found /boot/uInitrd **
   Skipping Armbian_community for failure retrieving initrd
   SCRIPT FAILED: continuing...
   ```
   U-Boot then falls through to EFI, then PXE, times out, and resets — forever.
   From the outside: **the SSD LED never lights and the board “stops after
   U-Boot.”**

`extlinux.conf` stores **absolute** paths, so no single file can be correct for
both the SD layout and the eMMC-partition layout.

## Why boot.scr fixes it

The rockchip64 boot script (`boot-rockchip64.cmd` → `boot.scr`) addresses every
file through `${prefix}`:

```
load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} ${prefix}Image
load ${devtype} ${devnum}:${distro_bootpart} ${fdt_addr_r}    ${prefix}dtb/${fdtfile}
```

U-Boot’s distro-boot sets `${prefix}` by trying `boot_prefixes="/ /boot/"` and
using whichever actually contains the files. So the **same** `boot.scr`:

- boots from an SD card where the files are under `/boot/…`, and
- boots from an eMMC boot **partition** where the files are at `/…`.

It also **always appends `rootwait`** (mandatory: the USB SSD needs several
seconds to enumerate), and reads `usbstoragequirks=` from `armbianEnv.txt` so
the USB-SATA quirk is a first-class variable, not a hand-edited kernel argument.

Because `armbian-install`’s `install_rewrite_bootenv` fully supports
`armbianEnv.txt`, dropping `SRC_EXTLINUX="yes"` is all it takes for the stock
split-emmc flow to produce a correct configuration.

> **Precedence caveat:** U-Boot’s `scan_dev_for_boot` tries `extlinux.conf`
> *before* `boot.scr`. If a partition somehow carries both, extlinux wins. This
> port ships no `extlinux/` directory at all, which the build was verified to
> honour (`extlinux/` absent, `boot.scr` present) before flashing.

## Recovering an already-deployed extlinux unit

If you have a board already installed the old way and don’t want to re-image,
`tools/board/armbian-install-extlinux-fixup.sh <boot-part> <root-part>` rewrites
the stale `extlinux.conf` in place (fixes both `root=` and the `/boot/` prefixes
and ensures `rootwait`). New deployments from this port never need it.

## The USB-SATA bridge

Because the rootfs lives on USB, the **USB-SATA bridge is the single
highest-risk component in this build** - more than the SSD, the board, or the
kernel. On most Armbian machines a flaky bridge means "the data disk dropped";
here it means "the machine did not come back".

Images do **not** override the transport: `usbstoragequirks` is left unset, so
the kernel behaves exactly as it would on stock Armbian. A bridge that
advertises UAS gets UAS; Armbian's own blacklist still covers the known-bad
Norelsys NS1066/NS1068 parts.

### Known-good bridges

Chips with a UAS implementation that is widely trusted on ARM SBCs:
**ASM1153E, ASM1351, JMS578, RTL9210**.

### If a disk misbehaves

Symptoms of a bad bridge, in escalating order: enumeration takes ~30 s longer
than usual; `dmesg` shows `uas_eh_abort_handler` and `reset SuperSpeed`; worst
case the board stops at

    Gave up waiting for root file system device.
    ALERT! UUID=... does not exist. Dropping to a shell!

The fix is one command, no rebuild, no re-image:

    tools/board/storage-transport.sh          # show current state
    tools/board/storage-transport.sh bot      # force BOT, then reboot
    tools/board/storage-transport.sh uas      # back to stock behaviour

BOT costs roughly 4-11x random IOPS on a bridge like that, but it always boots.

This is not hypothetical. The adapter formerly bundled with these units (OWC
`7825:a2a4`) fails exactly this way: across 20 warm reboots on **two different
cables**, 7 stalled for 30 s and one never brought the disk up at all.

## Disk health monitoring (optional, manual)

Images ship no `smartd` configuration. On a unit whose system disk really is a
USB-attached SATA drive, two lines enable it:

    apt install -y smartmontools
    DISK=/dev/$(lsblk -no pkname "$(findmnt -no SOURCE /)")
    echo "$DISK -d sat -a -o on -S on -W 4,45,60" > /etc/smartmontools/smartd.conf
    systemctl restart smartd

Three things make this manual rather than baked into the image:

* `DEVICESCAN` does not work here. Measured: plain `DEVICESCAN` reports *"NO
  devices found to scan"*, and `DEVICESCAN -d sat` reports *"/dev/sda open()
  failed: Not a SAT device"*. Only an explicit device entry registers the disk.
* Disk letters are not stable across boots, so the device must be resolved from
  whatever is actually mounted on `/` — which is what the `DISK=` line above
  does. Re-run it if you move the disk.
* eMMC and SD cards do not implement SMART at all. On a unit without a USB disk
  there is nothing to monitor and `smartd` exits 17, which systemd shows as a
  failed unit.

The attribute worth watching on this board is **`UDMA_CRC_Error_Count`**: it
counts errors on the SATA link, so a rising value means the cable, connector or
bridge is going marginal - the earliest warning available for the failure mode
described above. `Reallocated_Sector_Ct` and `Current_Pending_Sector` leaving 0
mean the flash itself is degrading.

There is no MTA in the image, so alerts go to the journal:

    journalctl -u smartd

**`docs/storage.md` is the full story**: every measurement, the boot run that
decided it, and the five hypotheses that were tested and refuted along the way.
