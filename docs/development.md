# Development guide — Armbian for XC3399FR v1.1a

This is the complete, self-contained guide for maintaining and extending this
board port. If you are new to the project, read it top to bottom once; after
that use it as a reference. The goal is that **anyone can continue development
safely** without having to rediscover how the board behaves.

> Golden rule: **the device tree in this repo is validated on real hardware.**
> Every change to it must be rebuilt, flashed, and re-tested on a board before
> it is trusted. Nothing here is "obviously correct" — the vendor documentation
> is wrong on several points and the reference configs carry junk (see below).

---

## 1. How this port is structured

Armbian is **not** forked. This repo is a thin overlay dropped on top of a
pinned checkout of [`armbian/build`](https://github.com/armbian/build):

```
userpatches/
  config/boards/xc3399fr.csc                     product overlay (KERNEL_TARGET + watchdog)
.github/workflows/build-image.yml                 CI: build → artifact + release
docs/                                             this guide + hardware/boot notes
assets/                                           the board photo + vendor logo
tools/                                            serial/UART + on-board helpers
```

Armbian sources the board file from **both** `config/boards/` and
`userpatches/config/boards/`, in that order, so our overlay only carries what
differs for the units we ship; everything else is inherited from the upstream
board file. The device tree comes entirely from upstream
(`patch/kernel/archive/<family>/dt/`) — this repository holds no copy. Nothing
in the framework is patched. This is the officially supported extension
mechanism.

**Two independent delivery channels exist:**

| Channel | Where | Purpose |
|---|---|---|
| This repo (private) | `github.com/liamhnam/armbian-xc3399fr` | your product image, with the board-specific hooks |
| Upstream | `armbian/build` (merged #10619) + `armbian.github.io` (merged #440) | the board itself, and Armbian's own rolling images |

Upstream carries the board: config, device trees for all three kernel branches,
photo and vendor logo. This repository carries only what is true of the units we
ship — `KERNEL_TARGET="current"` and the watchdog hook — plus the documentation
and tooling. Armbian sources the upstream board file first and this repo's
overlay second, so anything not set in the overlay tracks upstream for free.

---

## 2. The board in one screen (read before touching the DT)

Measured on real hardware, not from the datasheet (which is wrong):

- **RK3399**, **4 GB LPDDR4** (datasheet says "DDR3 2 GB" — false), eMMC HS400 ES.
- **The two USB 3.0 ports do not behave the same.** A bus-powered disk on
  `fe800000.usb` / `vcc5v0_otg` produced a disconnect storm; the same class of
  disk on `fe900000.usb` / `vcc5v0_host` is solid across long soaks. The cause
  is **not established** (`docs/storage.md` records what was and was not
  tested). **Always put a disk on the `vcc5v0_host` port.** Identify at runtime:
  `readlink -f /sys/class/block/sdX/device | grep -oE 'fe[89]00000\.usb'`.
- **No PCIe / no mSATA.** The PCIe PHY PLL never locks; the RK3399 has no SATA
  controller. `&pcie0`/`&pcie_phy` are disabled on purpose.
- **"4× RS232"** are an Exar XR21V1414 USB bridge → `/dev/ttyUSB0-3`.
- **Debug UART**: UART2, **1500000 baud, 8N1** (console `ttyS2`).
- **Wi-Fi/BT**: AP6256 (BCM4345/9). BT is `brcm,bcm4345c5` @ 1.5 Mbaud.

Full detail: [`hardware.md`](hardware.md). Boot/rootfs story:
[`install.md`](install.md).

---

## 3. Building an image

### 3a. In CI (recommended)

- Push to `main` (touching `userpatches/**` or the workflow), **or** run the
  **Build Armbian image (XC3399FR)** workflow from the Actions tab.
- On success the image is uploaded as a build **artifact** *and* published to the
  rolling **`latest`** pre-release (Releases page).
- Cutting a tag `vX.Y.Z` publishes an immutable, release-noted version:
  ```bash
  git tag v1.0.0 && git push origin v1.0.0
  ```
- The build takes **~1h45** on the free runners. It runs natively
  (`PREFER_DOCKER=no`) because Armbian's nested Docker cannot register the qemu
  binfmt handlers on GitHub runners — do not remove that flag (see §6).

### 3b. Locally (Debian/Ubuntu or WSL2, ~30 GB free)

```bash
git clone https://github.com/armbian/build armbian-build
cd armbian-build
git checkout 66dbc7af2a77d52ccd3fe2156a55687622848ea3   # the pinned ref, see the workflow env
cp -r /path/to/armbian-xc3399fr/userpatches/. userpatches/
./compile.sh build \
  BOARD=xc3399fr BRANCH=current RELEASE=trixie \
  BUILD_MINIMAL=yes BUILD_DESKTOP=no KERNEL_CONFIGURE=no \
  COMPRESS_OUTPUTIMAGE=sha,xz
```

The image lands in `output/images/`.

> **On a RAM-limited host (e.g. WSL with <8 GB), cap parallelism:**
> `CPUTHREADS=6 ./compile.sh build ...` — the default (`cores + cores/2`) will
> invoke the OOM killer during the kernel compile. A `-j24` build has hung
> machines during this project.

### 3c. Just rebuild the DTB (fast iteration on the device tree)

You don't need a full image build to test a DT change. In a checked-out kernel
worktree (`cache/sources/linux-kernel-worktree/6.18__rockchip64__arm64`):

```bash
cp patch/kernel/archive/rockchip64-6.18/dt/rk3399-xc3399fr.dts \
   arch/arm64/boot/dts/rockchip/
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip/rk3399-xc3399fr.dtb
```

Then copy the resulting `.dtb` to a running board's `/boot/dtb/rockchip/` and
reboot (see §5). This is the tight loop used throughout this port's bring-up.

---

## 4. Changing the device tree safely

The device tree lives **upstream** now, at
`patch/kernel/archive/rockchip64-{6.18,7.2,7.3}/dt/rk3399-xc3399fr.dts` in
`armbian/build` — this repository no longer carries a copy, so there is nothing
here to keep in sync. Change it with a PR to `armbian/build`, and keep all three
kernel versions byte-identical.

Every non-obvious value already carries an in-tree comment explaining the
evidence for it — **read the comment before changing a value**, and update it if
you change the value.

Process for any DT change:

1. Edit the `.dts`.
2. Rebuild the DTB (§3c). It must compile with **no warnings**.
3. Deploy to a board and **re-test the affected feature** (§5). For anything
   touching power/USB/PCIe/clocks, also re-run a cold boot.
4. If you changed the `model` string, rebuild and refresh
   `docs/rk3399-xc3399fr.reference.dtb` so the checked-in reference matches.
5. Update `README.md` / `docs/` if user-visible behavior changed.

Things that are **deliberately the way they are** — do not "fix" without
hardware proof:

- `&pcie0` / `&pcie_phy` **disabled** — no PCIe is routed; enabling them only
  produces `-110` probe noise every boot.
- `vcc5v0_host` / `vcc5v0_otg` are `regulator-always-on` — this is what revives
  the second USB3 port. The `st7735r` panel node from the reference config is
  removed because it held `gpio4 RK_PD1` (a USB VBUS enable) low.
- `sd-uhs-sdr12/25/50/104` all listed — without the slower modes a non-SDR104
  card drops to 50 MHz. `clock-frequency = 150 MHz` is the RK3399 ceiling;
  drop both to `100000000` if field cards show CRC retries (comment in the DTS).
- No `local-mac-address` — systemd derives a stable, unique MAC per unit from
  the machine-id. Pinning one would make every unit share a MAC.
- HYM8563 RTC, RT5640 codec, GT911 touch, IR receiver are **absent on purpose**
  (reference-board junk; the RTC was proven absent by an i2c scan).

Review history worth keeping: CodeRabbit flagged three inherited-from-`fine3399`
nits on the upstream PR. Two were fixed and verified on hardware before the
merge — the `pmic_int_l` pinctrl pin (corrected to `<1 RK_PC5 RK_FUNC_GPIO
&pcfg_pull_up>`) and four fixed regulators that were missing
`regulator-min/max-microvolt`. The third, a WiFi IRQ-type flag, was left alone:
it matches mainline `fine3399` and every RK3399 reference board, and changing it
without a reason is how a working port breaks. `vcc_phy` is likewise
deliberately left without voltage constraints — mainline evb/hugsun/roc,
`fine3399` and the vendor Android tree all do the same.

---

## 5. Testing on real hardware

The board is reachable three ways:

- **Debug UART**: COM/serial at **1500000 8N1**. Use `tools/serlog.ps1` to
  capture a full boot log, `tools/sh.ps1` to log in and run commands in one
  session (Windows/PowerShell helpers).
- **SSH**: over the board's DHCP lease. A fresh image asks you to set the root
  password on first boot.
- **scp**: to push a rebuilt DTB/kernel onto a running board.

Typical DT test loop:

```bash
# on the board, from your workstation:
scp rk3399-xc3399fr.dtb root@<board-ip>:/boot/dtb/rockchip/rk3399-xc3399fr.dtb
ssh root@<board-ip> 'sync; reboot'
# then watch the UART or re-ssh and check dmesg
```

**Acceptance checklist before trusting a build** (all verified during bring-up):

- `dmesg` clean (no `error`/`fail`/`HC died`/`-110`).
- Both USB3 ports enumerate SuperSpeed; a disk on the `vcc5v0_host` port
  survives a sustained read with 0 disconnects / 0 I/O errors.
- eth0 1000M full-duplex, `ethtool -S eth0` error counters all 0.
- HDMI connected + EDID; micro-SD, eMMC (HS400 ES), Wi-Fi scan, BT 5.0 all up.
- `/dev/watchdog0` present; if the watchdog hook is enabled, `systemctl show -p
  RuntimeWatchdogUSec` is non-zero.
- Reboot ×several and one **cold boot** (power-cycle), judging root/boot by
  **UUID**, not by `sd?` letter — the letters move between boots.

The **eMMC-boot + USB-SSD-system** scenario is the headline feature; test it
exactly as a customer would (§ `install.md`): flash SD → boot →
`armbian-install` → *Boot from eMMC, system on this disk* → remove SD → boot.

---

## 6. The two non-obvious CI facts (do not regress these)

1. **`PREFER_DOCKER=no`** in the build step. Armbian dockerises itself by
   default, but the nested container on a GitHub runner cannot register
   `binfmt_misc` (`update-binfmts` fails with EPERM), which the arm64-on-amd64
   cross build needs. Building natively on the runner (which has passwordless
   sudo) fixes it. Removing this flag brings the binfmt failure back.
2. **Artifact collection uses `find`, not a bare glob.** `COMPRESS_OUTPUTIMAGE`
   produces `*.img.xz`, so a literal `*.img` glob has no match and, under
   `set -e`, kills the step *after* the image already built. `find` never fails
   on a no-match.

The Armbian framework is **pinned** via `ARMBIAN_REF` in the workflow `env`.
To move to a newer framework: bump that SHA, run the build, and re-test on
hardware before tagging a release. Never float it on `main`/`HEAD` — an
unpinned framework can change the kernel version and U-Boot under you.

---

## 7. The board config (`xc3399fr.csc`) explained

- `BOOTCONFIG="fine3399-rk3399_defconfig"` — reuses fine3399's U-Boot defconfig.
  This is intentional and standard (many boards share defconfigs). The only
  visible consequence is the U-Boot banner/prompt saying `Fine3399` before the
  kernel loads; the OS is fully XC3399FR. Making U-Boot "pure" would mean
  shipping our own defconfig + U-Boot DT and **re-flashing the bootloader** —
  not worth the risk for a working product. See the report in the project
  history if you ever need it.
- **No `SRC_EXTLINUX="yes"`** — this is critical. The board uses
  `boot.scr` + `armbianEnv.txt` like 340 of Armbian's 362 boards. It is what
  makes `armbian-install` split-emmc work. Do **not** add extlinux back
  (`install.md` explains why in full).
- **`usbstoragequirks` is deliberately NOT set**, so the images behave like
  stock Armbian and Armbian's own Norelsys blacklist stays in effect (it is only
  auto-installed when the variable is **empty** — writing any value of our own
  would replace that list, not extend it). An earlier revision pinned the
  formerly-bundled `7825:a2a4` bridge to BOT; that came out when the cable
  stopped shipping, since a VID:PID quirk for hardware the customer does not own
  only costs everyone else 4-11x random IOPS. The measurements that motivated it
  are still worth reading — `storage.md` §6.
- Hook `post_family_tweaks__xc3399fr_watchdog` enables the hardware watchdog
  (`RuntimeWatchdogSec=30s`) for unattended 24/7 use. No Armbian board sets
  this, which is exactly why it is here and not in the upstream PR.
- **No smartd config is shipped**, and that is deliberate. A previous revision
  wrote `DEVICESCAN -d sat`, which measurement showed does not work: only an
  explicit device entry registers the disk, and hardcoding `/dev/sda` is unsafe
  because disk letters are not stable here. eMMC and SD do not implement SMART
  at all, so on a unit without a USB disk smartd would exit 17 and show as a
  failed unit for no reason. `install.md` documents the manual setup.

Both hooks are **product policy** and are intentionally absent from the upstream
PR version of this file. `upstream.md` records the full divergence list.

---

## 8. Cutting a release

1. Make sure `main` is green (Actions) and the `latest` pre-release has a good image.
2. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. CI builds and publishes a versioned GitHub Release with the `.img.xz` + `.sha`.
4. Give customers the release link. They flash the `.img.xz` (Etcher / RPi
   Imager), verify against the `.sha`, and follow the README quick-start.

---

## 9. Where to look when something breaks

| Symptom | Start here |
|---|---|
| Image won't build in CI | the failing step's log; check §6 regressions first |
| Board "stops after U-Boot", SSD LED off | `install.md` — almost always the extlinux/path issue or the wrong USB3 port |
| USB disk resets / xHCI "HC died" | check which port it is on — move it to `vcc5v0_host` / `fe900000.usb` (§2) |
| A feature regressed after a DT edit | rebuild DTB, diff against `docs/rk3399-xc3399fr.reference.dtb`, re-test (§4–5) |
| WiFi/BT missing | check the SDIO/uart0 nodes and that `armbian-firmware` is installed |
| Wrong kernel/U-Boot version | someone floated `ARMBIAN_REF`; re-pin it (§6) |

When in doubt: the vendor Android DTB
(`docs/rk3399_android_vendor.dts.txt`) is the source of most hardware facts —
**but it carries reference-board junk**, so never copy from it without
confirming against real hardware.
