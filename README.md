# uConsole CM5 on vanilla Raspberry Pi OS

Runs a ClockworkPi uConsole (Compute Module 5) on a **stock Raspberry Pi OS**
kernel. Hardware support is provided by out-of-tree **DKMS modules** plus
two **device-tree overlays**, so the kernel stays updatable
(DKMS rebuilds the modules on kernel upgrades).

Verified on kernel 6.12.75.

## What works

- Display (JD9365 / cwu50 DSI panel, 720x1280) + backlight
- AXP228 PMIC: regulators, battery gauge, ADC, Power button
- Keyboard / trackball (USB HID via the on-board MCU)
- Audio output, with driver-level speaker auto-mute on headphone insertion
- Volume / mute (PipeWire software mixer)

## How it works

The uConsole hardware that stock RPi OS doesn't know about is described by two
device-tree overlays and driven by out-of-tree modules:

- `overlay/uconsole-cm5-base-overlay.dts` - AXP228 PMIC on a bit-banged i2c bus,
  its regulators, battery and ADC, the ocp8178 backlight, and the DSI panel with
  explicit host byte/DPI clock assignments (these fixed the early black screen).
- `overlay/uconsole-audio-cm5-overlay.dts` - the RP1 audio output plus the AW8110
  speaker amplifier with a headphone-detect GPIO.

The DKMS package `uconsole-cm5` builds these modules (see VERSIONS for origin and
per-file status):

- `panel-cwu50`, `ocp8178_bl` - display panel and backlight (ClockworkPi drivers).
- `axp20x`, `axp20x-i2c`, `axp20x-regulator`, `axp20x_battery`, `axp20x_adc`,
  `axp20x-pek` - the AXP PMIC stack.
- `snd-soc-simple-amplifier` - mainline amplifier driver with a local addition:
  an optional hp-det GPIO that auto-mutes the speakers when headphones are plugged.

Everything vanilla RPi OS builds off the standard kernel headers; the AXP drivers
are needed because those symbols are disabled in the stock kernel config.

## Install

### 1. Flash the SD card

Flash stock Raspberry Pi OS (Trixie) with Raspberry Pi Imager. In the Imager
settings set:

- a username and password (used for SSH below)
- your Wi-Fi SSID and password

Write the card, put it in the uConsole, and power on. Wait for first boot to
finish (it resizes the filesystem and reboots once); the device then joins Wi-Fi.

### 2. Copy this project to the device

From your computer, in the directory that contains the `uconsole-cm5` folder

    scp -r uconsole-cm5 uconsole.local:/tmp/

### 3. Run the installer over SSH

    ssh uconsole.local
    /tmp/uconsole-cm5/install.sh

## Credits

This project only packages existing work as DKMS modules + device-tree overlays
for a vanilla kernel; the drivers themselves come from the following sources.

- **ClockworkPi** (Clockwork Tech LLC) - original panel (cwu50) and backlight
  (ocp8178) drivers, distributed as kernel patches. The DevTerm/uConsole panel
  driver family traces back to ClockworkPi's BSP (original cwd686 driver authored
  by Pinfan Zhu; Max Fierke did cleanup/rotation work on the related cwd686 for
  mainline). Repository: https://github.com/clockworkpi/uConsole

- **Rex (ak-rex)** - maintainer of the ClockworkPi kernel tree, APT repo and
  Bookworm/Trixie images used here as the reference for intended CM5 behavior.
  The rpi-6.12.y tree is where the integrated panel/AXP/audio sources were taken
  from. Repository: https://github.com/ak-rex/ClockworkPi-linux (branch rpi-6.12.y)

- **Mainline Linux / Raspberry Pi kernel** - the AXP20x PMIC stack (mfd,
  regulator, i2c, adc, pek) and the simple-amplifier base driver.
  https://github.com/raspberrypi/linux

- **This project** - the DKMS + overlay packaging for a stock kernel, the
  headphone auto-mute addition to simple-amplifier, and the PipeWire
  software-volume handling.
