# uConsole CM5 on vanilla Raspberry Pi OS

Runs a ClockworkPi uConsole (Compute Module 5) on a **stock Raspberry Pi OS**
kernel. Hardware support is provided by out-of-tree **DKMS modules** plus
two **device-tree overlays**, so the kernel stays updatable
(DKMS rebuilds the modules on kernel upgrades).

Verified on kernel 6.12.75 and 6.18.34.

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

The DKMS package `uconsole-cm5` builds these modules:

- `panel-cwu50`, `ocp8178_bl` - display panel and backlight (ClockworkPi drivers).
- `axp20x`, `axp20x-i2c`, `axp20x-regulator`, `axp20x_battery`, `axp20x_adc`,
  `axp20x-pek` - the AXP PMIC stack.
- `snd-soc-simple-amplifier` - mainline amplifier driver with a local addition:
  an optional hp-det GPIO that auto-mutes the speakers when headphones are plugged.

Everything vanilla RPi OS builds off the standard kernel headers; the AXP drivers
are needed because those symbols are disabled in the stock kernel config.

## Install

> In case you already have a custom ClockworkPi/Rex kernel installed, install these drivers first,
> (step 2) then follow "Switching from a custom kernel to the stock Pi kernel" below to move onto
> the stock kernel. When install.sh offers to reboot, decline — you'll reboot at the end of the
> kernel switch instead.

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

## Switching from a custom (ClockworkPi/Rex) kernel to the stock Pi kernel

If the device already runs a ClockworkPi/Rex image with a **custom kernel**, this
project is meant to run on the **stock Raspberry Pi kernel** instead. You can switch
an existing install over to the stock kernel rather than reflashing.

> ⚠️ **Verify package names on your device before running any of this.** Names differ
> by board and image, and removing a kernel before a working one is installed can
> leave the system unbootable. The commands below are a guide, not a verified
> one-shot procedure.

For CM5 (BCM2712) prefer `linux-image-rpi-2712` (+ `linux-headers-rpi-2712`) — it's
the native build (16K pages). The `linux-image-rpi-v8` build also boots and works on
CM5 (it's the 4K-page ARMv8 build; the bootloader still loads the correct CM5 device
tree by hardware detection), just slightly less optimal. Confirm the package is
available:

    apt policy linux-image-rpi-2712

### 1. Install the stock kernel FIRST (before removing anything)

    sudo apt update
    sudo apt install linux-image-rpi-2712 linux-headers-rpi-2712
    sudo apt install --reinstall raspi-firmware   # ensures the kernel is copied into /boot/firmware

### 2. Only then remove the custom kernel

    # find the custom kernel package name first:
    dpkg -l | grep -E 'linux-image|kernel'
    # then remove it (replace <clockworkpi-kernel-pkg> with the name from above):
    sudo apt remove <clockworkpi-kernel-pkg>

If the custom image pins/holds the kernel (apt pinning or `kernel=` in config.txt),
you may also need to remove that pin / that config.txt line so the stock kernel is
used at boot.

### 3. Reboot and verify

    sudo reboot
    # after boot:
    uname -r          # should show the stock ...-rpi-2712 kernel

After the switch, DKMS should rebuild the drivers for the stock kernel automatically.
If they're missing after reboot (usually because the stock kernel's headers weren't present for the automatic rebuild),
re-run install.sh to build them.

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

- **Custom kernel switch instructions** - switching was tested by [gnzl on reddit](https://www.reddit.com/r/ClockworkPi/comments/1ungpfy/comment/ow5j4ki/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button)
