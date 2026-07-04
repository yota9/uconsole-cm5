#!/usr/bin/env bash
# Add uConsole display rotation (DSI-2, 270 deg) to the Wayland session autostart.
set -euo pipefail
OUTPUT="${1:-DSI-2}"
TRANSFORM="${2:-270}"
LINE="wlr-randr --output ${OUTPUT} --transform ${TRANSFORM}"

# labwc (RPi OS Trixie default): ~/.config/labwc/autostart
LABWC="$HOME/.config/labwc/autostart"
mkdir -p "$(dirname "$LABWC")"
grep -qF "$LINE" "$LABWC" 2>/dev/null || echo "${LINE} &" >> "$LABWC"
echo "labwc autostart -> $LABWC:"; grep -n "wlr-randr" "$LABWC" || true

# if currently in a graphical session, apply immediately (optional)
if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wlr-randr >/dev/null 2>&1; then
  $LINE && echo "rotation applied to current session"
fi

echo "Rotation setup completed"
