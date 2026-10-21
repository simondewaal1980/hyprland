#!/usr/bin/env bash
#
# notification-status.sh — geeft het juiste pictogram voor de Waybar-module.
# De codepoints zijn Nerd Font / Font Awesome (via \u-escapes, zodat de
# broncode niet afhankelijk is van de editor).
#
set -euo pipefail

if makoctl mode 2>/dev/null | grep -qx 'do-not-disturb'; then
    printf '\uF1F6\n' # bell-slash
else
    printf '\uF0F3\n' # bell
fi
