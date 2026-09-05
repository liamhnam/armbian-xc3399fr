# Reproducing the measurements

Every number in `storage.md` came from the commands below, run on a v1.1a board
over the debug UART. If you change the device tree, the kernel branch, or the
bundled cable, re-run the relevant section rather than trusting the old table.

## 0. Getting a shell

The debug UART is **1500000 baud, 8N1**, console `ttyS2`.

    tools/serial/sh.ps1 -Port COM3 -Cmds @('uname -a','lsblk')

Two things that will waste your afternoon if you do not know them:

* **Do not send Ctrl-C while U-Boot is counting down.** It interrupts autoboot
  and strands the board at the `Fine3399 =>` prompt. `tools/serial/sh.ps1`
  detects that prompt and issues `boot` automatically; older copies did not.
* **USB bus numbers and `sda`/`sdb` letters are not stable across boots.**
  Resolve through sysfs or UUID, never by bus number.

To talk to U-Boot deliberately:

    tools/serial/uboot.ps1 -Cmds @('printenv boot_targets')

## 1. Which port is the disk on

This matters more than any tuning. See `storage.md` section 1.

    readlink -f /sys/class/block/sda/device | grep -oE 'fe[89]00000\.usb'

`fe900000.usb` is correct. `fe800000.usb` is the OTG rail and will kill the
xHCI controller under sustained load.

## 2. Transport and queue state

    tools/board/storage-transport.sh

Or by hand:

    cat /sys/block/sda/device/queue_depth      # 1 = BOT, 30 = UAS
    dmesg | grep 'scsi host0:'
    grep -H . /sys/block/sda/queue/{scheduler,nr_requests,max_sectors_kb,max_hw_sectors_kb,read_ahead_kb,rotational}

## 3. The benchmark set

`fio` is not installed by default:

    apt-get install -y fio

All runs use `--direct=1` so the page cache is out of the picture. Use a file
on the filesystem you actually care about (`/root` for the SSD rootfs,
`/emmc_storage` for the eMMC reference).

    F=/root/fiotest
    COMMON="--filename=$F --size=2G --direct=1 --ioengine=libaio --time_based --group_reporting"

    fio --name=rr1  $COMMON --rw=randread  --bs=4k --iodepth=1  --runtime=20
    fio --name=rr32 $COMMON --rw=randread  --bs=4k --iodepth=32 --runtime=20
    fio --name=rw1  $COMMON --rw=randwrite --bs=4k --iodepth=1  --runtime=20
    fio --name=rw32 $COMMON --rw=randwrite --bs=4k --iodepth=32 --runtime=20
    fio --name=sr1  $COMMON --rw=read      --bs=1M --iodepth=1  --runtime=15
    fio --name=sr8  $COMMON --rw=read      --bs=1M --iodepth=8  --runtime=15
    fio --name=sw8  $COMMON --rw=write     --bs=1M --iodepth=8  --runtime=15

    rm -f $F

**Let the drive settle between the random and sequential runs.** A sequential
read taken immediately after a heavy 4K random write pass reads far too low
(48 MB/s instead of 142 MB/s) because the SSD is still doing internal garbage
collection. That artifact caused a wrong conclusion once already.

Plain throughput, comparable with older `dd` numbers:

    dd if=/dev/zero of=/root/dd.tmp bs=1M count=1024 oflag=direct
    dd if=/root/dd.tmp of=/dev/null bs=1M iflag=direct
    rm -f /root/dd.tmp

## 4. Soak and data integrity

Stability, roughly a NAS/Docker mix:

    fio --name=soak --filename=/root/fiotest --size=4G --direct=1 \
        --ioengine=libaio --rw=randrw --rwmixread=70 --bs=4k --iodepth=32 \
        --numjobs=2 --runtime=600 --time_based --group_reporting

Integrity - writes then reads back and checks a CRC on every block, and stops
dead on the first mismatch:

    fio --name=vfy --filename=/root/fiotest --size=3G --direct=1 \
        --ioengine=libaio --rw=randwrite --bs=4k --iodepth=32 --numjobs=2 \
        --runtime=480 --time_based --verify=crc32c --verify_backlog=4096 \
        --verify_fatal=1 --group_reporting

Afterwards, `err=0` in the fio summary and this must be empty:

    dmesg | grep -E 'uas_eh|reset SuperSpeed|I/O error|EXT4-fs error'

## 5. SMART, before and after

`smartctl` cannot see a disk behind a USB-SATA bridge without being
told the transport:

    apt-get install -y smartmontools
    smartctl -i -d sat /dev/sda
    smartctl -A -d sat /dev/sda | grep -E 'Reallocated|CRC|Uncorrect|Pending|Total_LBAs'

Take this before and after a soak. The value that matters most is
`UDMA_CRC_Error_Count`: if it climbs during a run, the cable or the bridge is
marginal, and no amount of software tuning will fix that.

## 6. Boot reliability

This is the measurement that decided UAS vs BOT, and it is the one people skip
because it is slow. It needs repetition — a single clean boot proves nothing,
since the failure is probabilistic: about 35 % of warm reboots stall and about
5 % never bring the disk up at all.

    tools/board/bootloop.ps1 -N 10 -Tag UAS

Each cycle logs in, runs three **short** commands, writes one line to
`bootcycles.txt` **on the workstation**, then reboots:

    UAS boot=3 abort=0 qd=30 mode=UAS attach=4.606595

`abort=0` and `attach` under ~6 s is a clean boot. `abort=1` with `attach`
around 36 s is the known 30 s stall described in `storage.md` section 4.

The results are deliberately kept off the board. An earlier version of this
harness had the board append its own results to a file on the rootfs, using one
long compound shell command. Long command lines get corrupted over the
1.5 Mbaud UART: rows went missing and fields arrived mangled
(`mode=${M:-BOT}` came back as `m:BOT}`), which silently destroyed a whole run.
Short commands, host-side parsing.

To compare transports, run the loop once per transport, flipping with
`tools/board/storage-transport.sh uas|bot` and rebooting in between. Keep the
runs in the same session — comparing against numbers from a different day mixes
in kernel and firmware differences. The first line of a run still reflects the
*previous* boot, since a transport change only takes effect on the next one.

**Reboot, do not power-cycle.** Cold boots have been clean in every observation;
only warm reboots expose the UAS fault. Testing a unit by pulling the plug will
tell you it is healthy when it is not.

**Budget for the board getting stuck.** If UAS fails hard, the board lands in
the initramfs rescue shell and then stops answering the serial console
altogether — the loop will report `UNREACHABLE` for every remaining cycle and
only a power cycle brings it back. That is a result, not a broken harness.
