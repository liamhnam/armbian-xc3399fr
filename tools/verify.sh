#!/bin/bash
V=/tmp/verify.dts
echo "===== PHAI CO (mong doi >0) ====="
for k in vcc5v0_host vcc5v0_otg vcc_4g fan_pwr vcc_phy vdd_log; do
  printf '  %-14s %s\n' "$k" "$(grep -c "regulator-name = \"$k\"" $V)"
done
echo "===== PHAI KHONG CO (mong doi 0) ====="
for k in hym8563 st7735r rt5640 goodix pwm-fan ir-receiver spi@ff1d0000; do
  printf '  %-16s %s\n' "$k" "$(grep -ci "$k" $V)"
done
echo "===== TRANG THAI CAC KHOI ====="
for n in "pcie@f8000000" "ethernet@fe300000" "mmc@fe330000" "mmc@fe320000" "mmc@fe310000" "serial@ff370000" "hdmi@ff940000" "i2c@ff110000" "i2c@ff3d0000"; do
  st=$(awk -v n="$n" '$0 ~ n" \\{" {f=1} f && /status = /{print $3; exit} f && /^\t};/{print "(khong khai bao)"; exit}' $V)
  printf '  %-22s %s\n' "$n" "${st:-<khong thay>}"
done
echo "===== GPIO USB VBUS ====="
grep -B4 -A2 'regulator-name = "vcc5v0_otg"' $V | grep -E 'gpio|enable-active' | head -4
echo "===== LEDS ====="
grep -A3 'compatible = "gpio-leds"' $V | head -6
grep -E 'label = "xc3399fr' $V
