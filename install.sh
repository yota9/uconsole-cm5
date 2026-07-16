#!/usr/bin/env bash
#
# install.sh - install the ClockworkPi uConsole CM5 port on vanilla Raspberry Pi OS.
#
set -euo pipefail

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKDIR"

PKG="uconsole-cm5"
VER="0.1"
SRC_DKMS="/usr/src/${PKG}-${VER}"
BOOTDIR="/boot/firmware"
[ -d "$BOOTDIR" ] || BOOTDIR="/boot"
CONFIG_TXT="${BOOTDIR}/config.txt"

# Some images (e.g. Ubuntu's raspi-firmware A/B updates) set os_prefix= in
# config.txt so the bootloader loads the kernel, initramfs, cmdline AND
# overlays from a subdirectory (typically "current/") instead of BOOTDIR
# directly. Mirror that here so overlays land where the bootloader actually
# looks; config.txt itself always stays at the top level, unprefixed.
OS_PREFIX=""
if [ -f "$CONFIG_TXT" ]; then
  OS_PREFIX="$(awk '
    /^\[/ { sect=tolower($0); gsub(/[][]/,"",sect); next }
    /^[[:space:]]*os_prefix[[:space:]]*=/ && sect != "tryboot" {
      sub(/^[^=]*=/,""); print; exit
    }
  ' "$CONFIG_TXT")"
fi
OVERLAYS_DIR="${BOOTDIR}/${OS_PREFIX}overlays"

OVL_BASE="uconsole-cm5-base"
OVL_AUDIO="uconsole-audio-cm5"

log(){ printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[x]\033[0m %s\n' "$*"; exit 1; }

# ===========================================================================
# SYSTEM phase (runs as root - the script re-executes itself under sudo)
# ===========================================================================
phase_system() {
  [ "$(id -u)" = "0" ] || die "phase_system must run as root"
  log "System install"

  # 1. packages
  log "Packages (dkms, headers, dtc, wlr-randr)"
  local KVER; KVER="$(uname -r)"
  apt-get update
  apt-get install -y dkms device-tree-compiler wlr-randr brightnessctl
  if [ -e "/lib/modules/${KVER}/build" ]; then
    echo "  kernel headers for ${KVER} already present, skipping"
  else
    local DISTRO_ID="" DISTRO_ID_LIKE=""
    if [ -r /etc/os-release ]; then
      # shellcheck disable=SC1091
      . /etc/os-release
      DISTRO_ID="${ID:-}"; DISTRO_ID_LIKE="${ID_LIKE:-}"
    fi
    local FALLBACK_PKG="linux-headers-rpi-2712"
    case " $DISTRO_ID $DISTRO_ID_LIKE " in
      *ubuntu*) FALLBACK_PKG="linux-headers-raspi" ;;
    esac
    apt-get install -y "linux-headers-${KVER}" 2>/dev/null \
      || apt-get install -y "$FALLBACK_PKG" \
      || die "Could not install kernel headers for ${KVER} (tried linux-headers-${KVER} and ${FALLBACK_PKG}). Install matching kernel headers manually and re-run."
  fi
  # 2. DKMS modules
  log "DKMS: build and install ${PKG}-${VER}"
  if dkms status -m "$PKG" -v "$VER" 2>/dev/null | grep -q .; then
    dkms remove -m "$PKG" -v "$VER" --all || true
  fi
  rm -rf "$SRC_DKMS"
  cp -r "$WORKDIR/dkms" "$SRC_DKMS"
  dkms add   -m "$PKG" -v "$VER"
  dkms build -m "$PKG" -v "$VER"
  dkms install -m "$PKG" -v "$VER"
  depmod -a

  # 3. device-tree overlays
  log "Overlays -> ${OVERLAYS_DIR}"
  install -d "$OVERLAYS_DIR"
  local pair name dts
  for pair in \
     "${OVL_BASE}:overlay/uconsole-cm5-base-overlay.dts" \
     "${OVL_AUDIO}:overlay/uconsole-audio-cm5-overlay.dts" ; do
    name="${pair%%:*}"; dts="${pair##*:}"
    dtc -@ -I dts -O dtb -o "/tmp/${name}.dtbo" "$WORKDIR/$dts"
    install -m 0644 "/tmp/${name}.dtbo" "${OVERLAYS_DIR}/${name}.dtbo"
    echo "  ${OVERLAYS_DIR}/${name}.dtbo"
  done

  # 4. config.txt
  log "config.txt"
  if grep -qE '^[[:space:]]*dtoverlay=audremap-pi5' "$CONFIG_TXT" 2>/dev/null; then
    sed -i 's/^\([[:space:]]*dtoverlay=audremap-pi5\)/#\1  # replaced by uconsole-audio-cm5/' "$CONFIG_TXT"
    echo "  audremap-pi5 commented out"
  fi
  # spi0's CS0 line is GPIO8, which the panel overlay uses as its reset-gpio;
  # with spi0 enabled the SPI controller claims that GPIO at boot and the
  # panel fails to probe (-EBUSY). uConsole has no exposed SPI header, so
  # it's safe to disable.
  if grep -qE '^[[:space:]]*dtparam=spi=on' "$CONFIG_TXT" 2>/dev/null; then
    sed -i 's/^\([[:space:]]*dtparam=spi=on\)/#\1  # disabled: GPIO8 (CS0) conflicts with the uconsole-cm5-base panel reset-gpio/' "$CONFIG_TXT"
    echo "  dtparam=spi=on commented out (frees GPIO8 for the panel reset line)"
  fi
  local line
  for line in "dtparam=ant2" "dtoverlay=${OVL_BASE}" "dtoverlay=${OVL_AUDIO}"; do
    grep -qxF "$line" "$CONFIG_TXT" 2>/dev/null || { printf '%s\n' "$line" >> "$CONFIG_TXT"; echo "  + $line"; }
  done

  log "System part done."
}

# ===========================================================================
# USER phase (current user, their $HOME and graphical session)
# ===========================================================================
phase_user() {
  log "User setup (volume + rotation) for $(whoami)"
  # volume via PipeWire soft-mixer -> $HOME/.config/wireplumber/...
  if [ -x "$WORKDIR/scripts/audio/setup-volume-pipewire.sh" ]; then
    "$WORKDIR/scripts/audio/setup-volume-pipewire.sh" || warn "volume: PipeWire not active in this session? will apply on login"
  fi
  # rotation -> $HOME/.config/labwc/autostart
  if [ -x "$WORKDIR/scripts/setup-rotation.sh" ]; then
    "$WORKDIR/scripts/setup-rotation.sh" || warn "rotation: not applied now, will apply on session login"
  fi
}

# ===========================================================================
# Entry point
# ===========================================================================

# Internal helper invocation: `install.sh __system` - system phase only (under sudo).
# Not meant to be called directly; the main flow re-execs itself this way.
if [ "${1:-}" = "__system" ]; then
  phase_system
  exit 0
fi

# Normal run: always the same, ./install.sh
if [ "$(id -u)" = "0" ]; then
  die "Run ./install.sh as a NORMAL user (not under sudo/root).
    The script elevates via sudo for the system part and applies the user part
    (volume/rotation) to your session. Under root the user settings would land in /root."
fi

command -v sudo >/dev/null 2>&1 || die "sudo is required for the system part"

# Phase 1 - system (via sudo, re-exec ourselves with the helper argument):
log "Phase 1/2 - system (sudo password may be required)"
sudo "$WORKDIR/install.sh" __system

# Phase 2 - user (in the current session, where PipeWire is active):
log "Phase 2/2 - user"
phase_user

# Reboot
log "Done. A reboot is needed to apply the overlays and drivers."
read -r -p "Reboot now? [Y/n] " ans
case "${ans:-Y}" in
  [Nn]*) echo "Reboot later manually: sudo reboot" ;;
  *)     echo "Rebooting..."; sudo reboot ;;
esac
