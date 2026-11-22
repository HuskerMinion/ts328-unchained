# TS-328 hardware notes

| Block | Details | Driver in this tree |
|---|---|---|
| SoC | Realtek RTD1296, 4x Cortex-A53, 2 GB DDR4 | |
| SMP | firmware is PSCI v0.1 without function IDs; secondaries use a spin table with a 32-bit release register at 0x9801aa44 | `realtek,rtd1295-spin-table` enable method |
| Interrupts | ISO and MISC irq muxes | `irq-rtd1195-mux` |
| PCIe | 2 Gen2 slots; device MMIO goes through a 4 KiB translated window | `pcie-rtd129x` |
| LAN 1 | RTL8111 on PCIe slot 1 | mainline `r8169` |
| LAN 2 | SoC GMAC | `r8169` with an RTD1295 GMAC platform variant |
| SATA | bays 1-2: SoC AHCI ports 0/1; bay 3: ASMedia ASM106x on PCIe slot 2, port 1 | `ahci_rtd129x`, `phy-rtd129x-sata`, mainline `ahci` |
| eMMC | DesignWare MSHC 2.70a; the IDMAC never clears OWN and needs the vendor start sequence; ~15 MB/s read, ~7 MB/s write | `dw_mmc-rtd129x` |
| USB | DWC3 DRD + U3 host, Realtek USB2/USB3 PHYs; the common USB clock is only on if U-Boot used USB | mainline DWC3 and Realtek USB PHYs; `dwc3-rtk` reset and clock bring-up for RTD1295 |
| Front MCU | Weltrend WT61P803 on UART2, 115200 | mainline `qnap-mcu`, new `qnap,ts328-mcu` variant |
| RTC | Epson RX8010 on I2C | mainline `rtc-rx8010` |
| PMIC | GMT G2227: DCDC2 = CPU rail, LDO3 = L2 rail | `g2227-regulator` |
| CPU clock | SCPU PLL, 300 MHz - 1.4 GHz | `clk-rtd129x-scpu` + `cpufreq-dt` |
| Audio | speaker via the audio CPU (`bluecore.audio` firmware), RPC over shared memory | `rtd1295-rpc`, `rtd1295-ao` (ALSA) |
| Bay LEDs | green LEDs of bays 1-2 on SoC PWM 0 and 3 | `pwm-rtd1295` + `leds-pwm` |
| Fan, thermal | fan driven by the MCU; SoC thermal sensor | `qnap-mcu` hwmon, `rtd1295_thermal`, `platform/sbin/qnap-fan` |
| Power-off | MCU `@C0`, then the ACPU standby handshake | `rtd1295-acpu-poweroff` |
| Watchdog | SoC watchdog; reboot on a hard hang | `rtd119x_wdt` (keepalive fixed), systemd `RuntimeWatchdogSec=30s` |
| Buttons | reset and USB Copy on GPIOs; registered, the reboot key is ignored until its polarity is verified | `gpio-keys` |

## Boot loader facts

- U-Boot 2018 (Realtek), `bootdelay=0`, no serial input.
- Normal boot: `ext2load mmc 0:2` of `/boot/Image`, `realtek.dtb`,
  `initrd.boot`, `bluecore.audio`, each checked against a POSIX `cksum`
  file (`<crc> <size> <path>`).
- USB-copy held at power-on: the same files from `usb 0:2`, with
  `factory_recovery` appended to the command line.
- `booti` copies the kernel to DRAM base + `text_offset`, so the Image must
  use `text_offset = 0x200000` and end below the audio firmware at
  `0x1b00000`. gzip Images are limited to 20 MiB decompressed.
- The initrd is passed as `initrd=0x35000000,<size>` on the command line.

## Memory map items to keep

- Audio firmware at `0x01b00000`, plus the vendor RPC and TEE carveouts.
- 128 MiB audio-CPU heap at `0x17000000`.
- ramoops at `0x2f000000` (2 MiB), same layout as the vendor kernel.

## Serial console

Header J1: pin 1 = board TX, pin 4 = GND, 3.3 V, 115200 8N1. Output only:
pins 2 and 3 take no input, so there is no interactive console.
