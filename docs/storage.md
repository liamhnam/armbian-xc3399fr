# Storage: the USB-SATA bridge, UAS vs BOT, and what a bad bridge costs

This is the reasoning and the raw numbers behind the single most consequential
decision in this port: how the system disk is driven.

**Decision: ship stock behaviour. `usbstoragequirks` is deliberately left unset
in the board config.**

That means these images do exactly what any Armbian image does: a bridge that
advertises UAS and is not on Armbian's blacklist gets UAS. We do not override
the kernel either way.

This is a change from an earlier revision, which pinned the OWC `7825:a2a4`
bridge to BOT. That bridge really is broken (section 6), but units no longer
ship with it, and hardcoding a VID:PID quirk for hardware the customer probably
does not own would only cost everyone else 4-11x random IOPS for nothing.

Leaving the variable unset is also what keeps Armbian's own protection working:
`armbian-hardware-optimization` installs its Norelsys NS1066/NS1068 blacklist
**only when the variable is empty**, so writing any value of our own would
replace that list rather than add to it.

What this document is for, then, is not to justify a setting - it is the record
of what a bad USB-SATA bridge does to a board whose rootfs lives on USB, how to
recognise it, and how to fix it on a unit in the field. Section 6 is the part
worth reading.

---

## 1. The hardware in question

| | |
|---|---|
| Bridge | `7825:a2a4` - **Other World Computing "External SATA Hard Drive Adapter cable PA023U3"**. Formerly bundled with units; no longer shipped, kept here because it is what every measurement below was taken on |
| Disk used for validation | Netac SSD 256GB, SATA 3.2 6.0 Gb/s link |
| Port | `fe900000.usb` (`usbdrd3_1`), fed by `vcc5v0_host` / gpio4 `RK_PD1` |

This is a real branded product with a registered USB-IF vendor ID, not an
anonymous clone, and it is popular in home NAS builds. That is not in tension
with the findings below, for four reasons worth stating because they come up
every time someone doubts this document:

1. **Most people use these as data disks, not root disks.** A failed
   enumeration on a media drive means "replug it". A failed enumeration on the
   disk holding `/` means the machine does not come back. The failure in
   section 6 is fatal *because* the rootfs lives behind the bridge.
2. **The host controller is half of the negotiation.** UAS behaviour depends on
   the xHCI implementation as much as on the bridge. RK3399 uses a Synopsys
   dwc3, which is a very different animal from an Intel PCH. Bridges that are
   rock solid on x86 misbehave on ARM SBCs routinely - the entire
   `usb-storage.quirks=...:u` folklore of the Raspberry Pi 4 community exists
   for this reason.
3. **The kernel's blacklist is sparse, not a certification.** `unusual_uas.h`
   in mainline contains 25 devices in total. Absence from it means nobody
   upstreamed a report, not that a device was verified good. `7825:a2a4`
   appears in no mainline quirk table at all.
4. **Self-healing faults do not get reported.** On a data disk the 30 s stall
   happens during hotplug, the kernel recovers, and the user files nothing.

So if a customer reports a disk that sometimes will not come up, forcing BOT
with `usb-storage.quirks` is not an exotic workaround - it is the same thing the
homelab community already does with cables like this, and
`tools/board/storage-transport.sh bot` does it in one command.

### The port matters more than anything else here

The two USB 3.0 ports are **not** interchangeable:

| Port | VBUS switch | Behaviour with a 2.5 inch SSD |
|---|---|---|
| `fe800000.usb` (`usbdrd3_0`) | `vcc5v0_otg`, gpio4 `RK_PC6` | Drops the bus / re-enumerates every ~30 s at idle. Under load it kills the **xHCI controller** (`HC died`) after 18-220 GB and needs a reboot. |
| `fe900000.usb` (`usbdrd3_1`) | `vcc5v0_host`, gpio4 `RK_PD1` | 127 GiB continuous read at 207-252 MB/s: 0 disconnects, 0 `HC died`, 0 I/O errors. |

The cause is the OTG rail's power switch, not the cable and not the device
tree - proven by moving the same SSD to the OTG port and watching it take down
both xHCI controllers. `over_current_count` always reads 0 because the board
does not wire the fault line back to the SoC, so the kernel never reports
over-current.

**Mark the correct port on the enclosure before shipping.** Identify it at
runtime with:

    readlink -f /sys/class/block/sda/device | grep -oE 'fe[89]00000\.usb'

USB bus numbers (`usb2`, `usb4`, ...) are **not stable across boots** and
neither are `sda`/`sdb` letters. Always resolve through sysfs or UUID, never by
bus number. Every mount in this image already uses UUIDs.

---

## 2. UAS vs BOT in one paragraph

A USB mass-storage device can be driven two ways. **BOT** (bulk-only
transport) sends one command per USB round trip - queue depth 1, no
overlapping. **UAS** (USB Attached SCSI) allows a real command queue. On this
bridge the kernel negotiates queue depth 30 under UAS and 1 under BOT. Setting
`usb-storage.quirks=7825:a2a4:u` forces BOT (`u` = `US_FL_IGNORE_UAS`).

---

## 3. Measurements

All `fio` runs used `--direct=1 --ioengine=libaio --time_based --runtime=20`,
block size 4K, on the mounted rootfs. The eMMC column was measured on
`/emmc_storage` (the same physical eMMC the OS used before moving to the SSD)
as a reference point.

| Test | SSD, BOT | SSD, UAS | eMMC (HS400 ES) |
|---|---|---|---|
| randread 4K QD1 | 1 400 IOPS / 701 us | 2 074 IOPS / 472 us | 4 753 IOPS / 204 us |
| randread 4K QD32 | 2 011 IOPS (8.0 MB/s) | **22 100 IOPS (86.5 MB/s)** | 14 800 IOPS (57.9 MB/s) |
| randwrite 4K QD1 | 2 646 IOPS | **7 184 IOPS** | 6 855 IOPS |
| randwrite 4K QD32 | 4 655 IOPS (18.2 MB/s) | **20 500 IOPS (80.2 MB/s)** | 11 700 IOPS (45.7 MB/s) |
| seq read 1M QD1 | 80.6 MB/s | 142 MB/s | 75.8 MB/s |
| seq read 1M QD8 | - | 202 MB/s | - |
| seq write 1M QD8 | - | 331 MB/s | - |
| dd 1 GiB direct write | - | 244 MB/s | 55.2 MB/s |
| dd 1 GiB direct read | - | 198 MB/s | 260 MB/s |
| `queue_depth` | 1 | 30 | - |
| `nr_requests` | 2 | 60 | - |

Read the table like this:

* **Random I/O is where the decision is made.** BOT is 4-11x slower than UAS,
  and 2.5-7x slower than the 14.6 GB eMMC the customer is migrating *away*
  from. Shipping BOT means "you upgraded to an SSD and Docker got slower".
* **Sequential does not decide anything.** The box has 1 GbE, which caps at
  about 118 MB/s. Both transports clear that comfortably, so for the NAS half
  of the workload the disk is never the bottleneck - the network is.
* One early measurement of 48 MB/s for UAS sequential read was an artifact of
  running immediately after a heavy 4K random write pass, while the SSD was
  still doing internal garbage collection. Re-measured on a quiescent drive it
  is 142 MB/s (QD1) / 202 MB/s (QD8).

### Endurance and integrity

Runtime behaviour was tested separately from enumeration, because the two turn
out to be completely different stories.

* **60 min `randrw` 70/30, QD32, 2 jobs, on UAS: 59.3 GiB moved (41.5 GiB read
  + 17.8 GiB written), `err=0`, and not one new kernel event.** `uas_eh_abort`
  stayed at 1 and `reset SuperSpeed` stayed at 1 for the whole hour - both of
  those being the single enumeration event from boot, not runtime faults.
* 8 min `randwrite` QD32, 2 jobs, with `--verify=crc32c --verify_fatal=1`:
  about 14 GB written and read back byte-verified, `err=0`, zero kernel errors.
* 10 min `randrw` 70/30, QD32, 2 jobs: 10.5 GB moved, `err=0`, zero kernel
  errors.
* SMART before and after every run: `Reallocated_Sector_Ct` 0,
  `Reallocated_Event_Count` 0, `Current_Pending_Sector` 0,
  `Offline_Uncorrectable` 0, and `UDMA_CRC_Error_Count` **unchanged at 10** -
  the SATA link accumulated no new CRC errors under sustained load.

**Once it is up, UAS on this bridge is clean and fast.** The defect is confined
entirely to enumeration.

The honest limit of that claim: an hour is an hour, not a month. Nothing here
rules out a rare runtime fault on a longer timescale, and a runtime USB reset
*would* be serious - `errors=remount-ro` would drop the rootfs to read-only.
What can be said is that across roughly 80 minutes of sustained QD32 load,
including a full byte-verified pass, the transport never faltered once.

---

## 4. The actual defect

On a large fraction of boots, UAS enumeration stalls:

    [    4.12] scsi host0: uas
    [    4.12] scsi 0:0:0:0: Direct-Access     Netac SS D 256GB
    [   35.83] sd 0:0:0:0: [sda] tag#13 uas_eh_abort_handler 0 uas-tag 1 inflight: CMD IN
    [   35.83] sd 0:0:0:0: [sda] tag#13 CDB: opcode=0x25 25 00 00 00 00 00 00 00 00 00
    [   35.86] scsi host0: uas_eh_device_reset_handler start
    [   35.97] usb 4-1: reset SuperSpeed USB device number 2 using xhci-hcd
    [   36.00] scsi host0: uas_eh_device_reset_handler success
    [   36.09] sd 0:0:0:0: [sda] Attached SCSI disk
    [   36.58] EXT4-fs (sda1): mounted filesystem ... ro
    [   38.14] EXT4-fs (sda1): re-mounted ... r/w

The first data-returning command after enumeration hangs until the 30 s SCSI
timeout, the kernel resets the device, and the disk then *usually* attaches.

When it recovers, the damage is genuinely limited: the disk does not attach
until after the reset, so there is no mounted filesystem to corrupt, and the
only cost is about +31 s of boot time.

**But it does not always recover.** That is the whole point, and it was only
found by repeating the boot enough times - see section 6. Do not conclude from
a handful of successful boots that this failure mode is benign; the first nine
boots of the decisive run all recovered.

One belief that turned out to be wrong and is worth stating plainly: **`rootwait`
does not wait forever.** Debian's initramfs retries `local-block` a bounded
number of times and then gives up with `ALERT! UUID=... does not exist`. A long
enough enumeration failure is an unbootable machine, not a slow boot.

---

## 5. Hypotheses tested and refuted

Every one of these was tried on real hardware and **did not work**. They are
recorded so nobody burns the time again.

| Hypothesis | How it was tested | Result |
|---|---|---|
| Specific to `READ CAPACITY(16)` | `usb-storage.quirks=7825:a2a4:e` (`NO_READ_CAPACITY_16`) | Refuted. The kernel falls back to `READ CAPACITY(10)` (`opcode=0x25`) and *that* hangs instead, at the same 35.83 s mark. |
| The bridge chokes on `REPORT OPCODES` | `...:f` (`NO_REPORT_OPCODES`) | Refuted. Identical stall. |
| ATA pass-through wedges it | `...:t` (`NO_ATA_1X`) | Refuted. Identical stall. Also **do not ship `t`**: it disables SAT, which is how `smartctl -d sat` reads the disk. |
| USB3 link power management (U1/U2) | `usbcore.quirks=7825:a2a4:k` (`NO_LPM`), confirmed applied via `/sys/module/usbcore/parameters/quirks` | Refuted, and it is a no-op: the kernel already prints `usb usb2: We don't know the algorithms for LPM for this host, disabling LPM`. LPM was never enabled. |
| U-Boot's failed USB probe leaves the bridge wedged (`0 Storage Device(s) found`) | `setenv boot_targets mmc0; saveenv`, then 5 boots with U-Boot provably never scanning USB | Refuted. Still stalled on 2 of 4 recorded boots. |

Conclusion: **the fault is in the bridge's own UAS firmware and cannot be
fixed from Linux.** The only lever is UAS on or off.

### Block-layer tuning is also a dead end

Measured, not assumed:

* Scheduler under UAS: `bfq` 20.1k, `mq-deadline` 20.8k, `none` 20.7k IOPS
  (randread 4K QD32) - within noise. Leave the default.
* Scheduler under BOT: `none` is **10% slower**, because `nr_requests` drops
  from 2 to 1 and the block layer loses its last bit of overlap.
* `max_sectors_kb` is already at the hardware maximum (1024 under BOT, 512
  under UAS - `max_hw_sectors_kb` confirms). Nothing to raise.
* `read_ahead_kb` already defaults to 2048 (BOT) / 1024 (UAS).
* `rotational` reads 1 for this device; forcing 0 changed nothing measurable.
* The rootfs is already mounted `noatime,commit=120` by `armbian-install`.

---

## 6. Boot reliability - the measurement that decided it

Ten consecutive reboots with UAS enabled, nothing else changed
(`tools/board/bootloop.ps1 -N 10 -Tag UAS`):

    UAS boot=1  abort=1 qd=30 attach=36.098160
    UAS boot=2  abort=1 qd=30 attach=36.099142
    UAS boot=3  abort=0 qd=30 attach=4.606595
    UAS boot=4  abort=0 qd=30 attach=4.332540
    UAS boot=5  abort=0 qd=30 attach=4.449649
    UAS boot=6  abort=0 qd=30 attach=4.541883
    UAS boot=7  abort=1 qd=30 attach=36.111223
    UAS boot=8  UNREACHABLE
    UAS boot=9  UNREACHABLE
    UAS boot=10 UNREACHABLE

Boot 8 is the one that matters. Its UART capture ends:

    Begin: Running /scripts/local-block ... done.      (x30)
    Gave up waiting for root file system device.  Common problems:
     - Boot args (cat /proc/cmdline)
       - Check rootdelay= (did the system wait long enough?)
     - Missing modules (cat /proc/modules; ls /dev)
    ALERT!  UUID=c95c75f7-c21b-4abb-bcec-c6dc0032d69b does not exist.
    Dropping to a shell!

The disk never appeared. The board sat in the initramfs rescue shell - which is
why boots 9 and 10 recorded nothing and their UART captures are 0 bytes - and
then stopped responding to the serial console entirely. It needed a power cycle.

Tally: **4 clean, 3 stalled and recovered, 1 hard failure, then stuck.**

The same run immediately afterwards with BOT, same board, same cable, same port,
same session - `tools/board/storage-transport.sh bot` and nothing else changed:

    BOT boot=2  abort=0 qd=1 attach=5.228144
    BOT boot=3  abort=0 qd=1 attach=5.420180
    BOT boot=4  abort=0 qd=1 attach=5.163876
    BOT boot=5  abort=0 qd=1 attach=5.438937
    BOT boot=6  abort=0 qd=1 attach=5.197298
    BOT boot=7  abort=0 qd=1 attach=5.206964
    BOT boot=8  abort=0 qd=1 attach=5.515123
    BOT boot=9  abort=0 qd=1 attach=5.206648
    BOT boot=10 abort=0 qd=1 attach=5.345285

(Boot 1 of that run is omitted: it was still the previous UAS boot, because a
transport change only takes effect on the next one.)

Nine warm reboots, zero aborts, enumeration between 5.16 s and 5.52 s - a spread
of 0.35 s. Compare that with UAS, where "attach" is either about 4.4 s or about
36.1 s depending on the coin flip, and occasionally never.

### Confirmed on a second cable

The obvious objection is that one bad cable proves nothing about the model,
especially since this is a popular branded product. So the whole run was
repeated with a **different cable from the same batch**, same SSD, same port,
same board:

    UAS2 boot=2  abort=0 qd=30 attach=4.429487
    UAS2 boot=3  abort=0 qd=30 attach=4.573698
    UAS2 boot=4  abort=1 qd=30 attach=36.101672
    UAS2 boot=5  abort=0 qd=30 attach=4.573057
    UAS2 boot=6  abort=0 qd=30 attach=4.410653
    UAS2 boot=7  abort=0 qd=30 attach=4.261772
    UAS2 boot=8  abort=1 qd=30 attach=36.123265
    UAS2 boot=9  abort=0 qd=30 attach=4.322678
    UAS2 boot=10 abort=1 qd=30 attach=36.085778
    UAS2 boot=11 abort=1 qd=30 attach=36.151384

Four stalls in ten, at 36.09-36.15 s - the same signature, to within 70 ms of
the first cable. The fault is a property of the bridge, not of one defective
unit.

### Combined

| Configuration | Warm reboots | Stalled ~30 s | Failed to boot |
|---|---|---|---|
| BOT | 9 | **0** | **0** |
| UAS, cable 1 | 10 | 3 | **1** |
| UAS, cable 2 | 10 | 4 | 0 |
| **UAS, total** | **20** | **7 (35 %)** | **1 (5 %)** |

Five percent sounds survivable until it is put on a calendar. A box that reboots
once a month for updates has roughly a 46 % chance of needing someone to drive
out to it within a year. That is the number that decides this, not the IOPS
table.

That table is the entire decision. A NAS or home server that has a ~5 %
chance per boot of not coming back is worse than a NAS that is slower at 4K
random I/O, because the first failure mode needs a human and the second does
not.

Note how easily this was missed: seven boots in a row behaved, including three
that stalled and recovered exactly as the benign theory predicted. Repetition
found it; reasoning did not.

### Cold boot is not the same as reboot

Every failure above happened on a **warm** reboot (`systemctl reboot`). Cold
boots - power removed and reapplied - have been clean in every observation,
enumerating in about 4.3-4.7 s with no abort. A plausible reason is that a warm
reboot never drops VBUS on the USB port, so the bridge carries state from the
previous session into the kernel's fresh enumeration.

This is worth knowing when reproducing the fault, and it is also a trap: a
technician who tests a unit by pulling the plug a few times will conclude the
board is fine. It is the reboots - kernel updates, `apt` upgrades, remote
restarts, watchdog resets - that expose it, and those are exactly the events
nobody is standing next to the machine for.

---

## 7. Switching transports

Shipped images pin nothing - the kernel decides. Override it per unit when a
bridge misbehaves:

    tools/board/storage-transport.sh          # show what is in effect
    tools/board/storage-transport.sh bot      # force BOT, then reboot
    tools/board/storage-transport.sh uas      # back to stock behaviour

or by hand in `/boot/armbianEnv.txt`:

    usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u,0x7825:0xa2a4:u   # BOT
    usbstoragequirks=0x2537:0x1066:u,0x2537:0x1068:u                   # UAS

Confirm after reboot:

    cat /sys/block/sda/device/queue_depth     # 1 = BOT, 30 = UAS
    dmesg | grep 'scsi host0:'                # 'uas' or 'usb-storage'

**Never ship a unit whose bridge has not survived a repeated-reboot test.**
Section 6 is what one bad bridge does, and seven consecutive good boots did not
predict it.

Keep the two Norelsys entries whenever you write the variable.
`armbian-hardware-optimization` only injects its own blacklist when the value is
**empty**, so a bare `usbstoragequirks=<vid>:<pid>:u` silently drops Armbian's
protection for those bridges. Leaving it unset - the shipped default - is the
one case where you get Armbian's list for free.

### If you ever need both speed and reliability

The bridge is the defect, not the board, the port, the SSD, or Linux. A bridge
with a working UAS implementation (ASM1153E, ASM1351, JMS578, RTL9210) would
give UAS throughput with no boot risk. That is a purchasing decision, not a
software one - as long as the `7825:a2a4` cable is the one in the box, BOT is
the only safe configuration.

---

## 8. Monitoring, because these run unattended

The image already sets these up; verify them when debugging a unit.

    systemctl show -p RuntimeWatchdogUSec --value   # 30s - hardware watchdog is fed
    findmnt -n -o SOURCE,OPTIONS /                  # must contain errors=remount-ro
    smartctl -A -d sat /dev/sda                     # -d sat is required behind USB
    systemctl status fstrim.timer                   # weekly TRIM

What to alert on:

* `uas_eh` or `reset SuperSpeed` in `dmesg` **at runtime**. A boot-time
  occurrence is the known, harmless case described in section 4.
* `UDMA_CRC_Error_Count` increasing - that means a marginal cable or bridge,
  and it is the earliest warning you will get.
* `Reallocated_Sector_Ct` or `Current_Pending_Sector` leaving 0.
