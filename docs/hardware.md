# XC3399FR v1.1a — hardware notes

Everything here was measured on a live board over the debug UART, not taken from
the vendor datasheet (which is wrong on several counts). GPIO names use the
Rockchip convention: bank + `RK_Pxy` (e.g. `gpio4 RK_PD1`).

## SoC and memory

- **Rockchip RK3399** — 2× Cortex-A72 (up to 1.8 GHz) + 4× Cortex-A53 (up to
  1.416 GHz), Mali-T860 GPU (up to 800 MHz). Standard RK3399 bin, **not** OP1;
  the port deliberately does not use the `rk3399-op1` OPP table.
- **4 GB LPDDR4** as 2×2048 MB @ 856 MHz. The silkscreen/datasheet claim of
  “DDR3 2 GB” is incorrect — confirmed by the DDR init banner and `free`.
- **eMMC 14.6 GiB**, running **HS400 Enhanced Strobe** @ 200 MHz (~267 MB/s).

## Storage

| Device | Node | Notes |
|---|---|---|
| eMMC | `&sdhci` (`mmcblk2`) | HS400 ES, 8-bit, non-removable |
| micro-SD | `&sdmmc` (`mmcblk1`) | card-detect `gpio0 RK_PA7`, SDR12/25/50/104 advertised; a fast card runs SDR50 @ 100 MHz |
| SDIO Wi-Fi | `&sdio0` | AP6256, capped at 50 MHz like the vendor tree |

## Power rails (regulators added/corrected by this port)

| Regulator | Enable GPIO | Purpose |
|---|---|---|
| `vcc5v0_host` | `gpio4 RK_PD1`, active-high | VBUS for the `fe900000.usb` USB3 port |
| `vcc5v0_otg` | `gpio4 RK_PC6`, active-high | VBUS for the `fe800000.usb` USB3 port |
| `vcc_phy` | `gpio0 RK_PB4`, active-high | RTL8211E Ethernet PHY |
| `fan_pwr` | `gpio2 RK_PD4`, active-high | chassis fan header (GPIO, not PWM) |
| `vcc_4g` | `gpio4 RK_PD2`, active-high | 3V3 to the mini-PCIe/4G slot |
| `vdd_log` | PWM2, inverted, 25 µs | logic rail; floor pinned to 1.0 V per vendor |

> The generic/fine3399 config leaves the USB3 VBUS-enable GPIOs undescribed
> (floating) and additionally routes `gpio4 RK_PD1` to an `st7735r` panel’s
> active-low reset, which holds VBUS low. That is why one USB3 port appears dead
> on the generic config. This port describes both rails as always-on regulators
> and removes the panel node.

## USB — the two USB 3.0 ports are not equal

| Port | Controller | VBUS rail | Use for a 2.5″ SSD? |
|---|---|---|---|
| left/back | `fe900000.usb` (usbdrd3_1) | `vcc5v0_host` | **Yes** — 127 GiB sustained read, 0 errors |
| the other | `fe800000.usb` (usbdrd3_0) | `vcc5v0_otg` | **No** — OTG rail browns the drive out under load; the drive resets ~every 30 s and can hang the xHCI controller |

Identify at runtime:
```bash
readlink -f /sys/class/block/sda/device | grep -oE 'fe[89]00000\.usb'
```
`over_current_count` stays 0 because no fault pin is routed to the SoC, so the
kernel never reports over-current — the symptom is a plain disconnect/reset.

The four “RS232” ports are an **Exar XR21V1414** USB-to-quad-UART bridge behind
an onboard USB 2.0 hub, exposed as `/dev/ttyUSB0-3`.

## Networking

- **Ethernet:** RTL8211E on RGMII (`&gmac`). Board-specific skew
  `tx_delay = 0x27`, `rx_delay = 0x1d`, reset on `gpio3 RK_PB7` active-low.
  No MAC is fused; systemd derives a stable per-unit MAC from the machine-id,
  so no `local-mac-address` is pinned (it would be identical on every unit).
- **Wi-Fi/BT:** AP6256 = BCM4345/9. Wi-Fi on SDIO (`brcmfmac`), Bluetooth on
  `&uart0` as `brcm,bcm4345c5` @ 1.5 Mbaud (BT 5.0). Enable/wake GPIOs:
  BT-enable `gpio0 RK_PB1`, host-wake `gpio0 RK_PA4`, dev-wake `gpio2 RK_PD2`;
  Wi-Fi reg-on `gpio0 RK_PB2`, host-wake `gpio0 RK_PA3`.

## Display

- **HDMI** via `&hdmi` + `&vopb`/`&vopl`; DDC on `&i2c3`; HDMI audio via
  `&hdmi_sound`/`&i2s2`. EDID reads correctly; tested to 2560×1440.
- Optional LVDS would go through a TC358775 DSI-to-LVDS bridge (not wired up in
  this port — needs real panel timings). Backlight: PWM0, enable `gpio4 RK_PD5`.

## LEDs, keys, misc

| Function | GPIO |
|---|---|
| power LED (green) | `gpio2 RK_PA2` |
| sys LED (heartbeat) | `gpio1 RK_PA4` |
| status LED (disk-activity) | `gpio2 RK_PA4` |
| power key | `gpio0 RK_PA5`, active-low |
| poweroff | `gpio1 RK_PA5`, active-high |
| UART4 header (3.3 V TTL) | `&uart4` → `/dev/ttyS4` |

- **Watchdog:** the RK3399 Synopsys DesignWare watchdog is enabled by mainline
  `rk3399-base.dtsi`; this port makes systemd feed it (`RuntimeWatchdogSec=30s`).
- **Thermal:** hardware shutdown left at the mainline 95 °C default (the vendor
  raises it to 120 °C). Peak measured under full CPU+GPU+IO+network stress was
  83.9 °C with no throttling.

## Things that do NOT exist on this board (removed from the DT)

- **PCIe / mSATA:** no PCIe is routed (the PHY PLL never locks) and the RK3399
  has no SATA controller, so an mSATA card can never work. The mini-PCIe slot is
  USB-signalled only (4G modems). `&pcie0`/`&pcie_phy` are disabled to stop the
  `-110` probe failure logged on every boot.
- **HYM8563 RTC:** the vendor Android tree declares one at i2c0 `0x51`, but an
  I²C scan shows only `0x1b/0x40/0x41` — it is reference-board junk and is absent.
- **RT5640 codec, GT911 touch, IR receiver:** reference-board leftovers, removed.
