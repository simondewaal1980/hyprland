#!/usr/bin/env bash
#
# wallpaper-rotate.sh — kies een andere wallpaper en pas het thema aan.
#
# Wordt elke 10 minuten aangeroepen door de systemd-user-timer
# hyprland-wallpaper-rotate.timer. Handmatig: Super+Shift+W.
#
# Gebruik:
#   wallpaper-rotate.sh [--notify]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/hypr-env.sh"

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/.local/share/wallpapers}"
HYPR_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"

notify=false
[[ "${1:-}" == "--notify" ]] && notify=true

shopt -s nullglob
imgs=(
    "${WALLPAPER_DIR}"/*.jpg "${WALLPAPER_DIR}"/*.jpeg
    "${WALLPAPER_DIR}"/*.png "${WALLPAPER_DIR}"/*.webp
)
shopt -u nullglob

if [[ ${#imgs[@]} -eq 0 ]]; then
    echo "wallpaper-rotate: geen afbeeldingen in ${WALLPAPER_DIR}" >&2
    exit 1
fi

current=""
if [[ -f "${HYPR_CACHE}/current-wallpaper" ]]; then
    current="$(<"${HYPR_CACHE}/current-wallpaper")"
elif [[ -f "${WAL_CACHE}/colors.json" ]]; then
    current="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wallpaper",""))' \
        "${WAL_CACHE}/colors.json" 2>/dev/null || true)"
fi

candidates=()
for f in "${imgs[@]}"; do
    [[ "$(readlink -f "${f}")" == "${current}" ]] || candidates+=("${f}")
done
[[ ${#candidates[@]} -gt 0 ]] || candidates=("${imgs[@]}")

if command -v shuf >/dev/null 2>&1; then
    next="$(printf '%s\n' "${candidates[@]}" | shuf -n 1)"
else
    next="${candidates[$((RANDOM % ${#candidates[@]}))]}"
fi

echo "wallpaper-rotate: $(date '+%F %T') -> $(basename "${next}")"
"${SCRIPT_DIR}/set-wallpaper.sh" "${next}"

if ${notify}; then
    notify-send -i "${next}" "Wallpaper" "$(basename "${next}" .jpg)" 2>/dev/null || true
fi
