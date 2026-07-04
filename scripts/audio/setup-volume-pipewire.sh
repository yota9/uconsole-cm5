#!/usr/bin/env bash
# Enable software volume/mute for RP1AudioOut via PipeWire/WirePlumber.

set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/51-rp1-soft-mixer.conf"
DEST_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"

mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST_DIR/51-rp1-soft-mixer.conf"
echo "installed: $DEST_DIR/51-rp1-soft-mixer.conf"

systemctl --user restart wireplumber
echo "wireplumber restarted."
