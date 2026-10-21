#!/usr/bin/env bash
#
# toggle-dnd.sh — zet meldingen (mako) aan of uit.
#
set -euo pipefail

if makoctl mode | grep -qx 'do-not-disturb'; then
    makoctl mode -s default
    notify-send "Meldingen" "Weer aan" 2>/dev/null || true
else
    makoctl mode -s do-not-disturb
    notify-send "Meldingen" "Niet storen" 2>/dev/null || true
fi
