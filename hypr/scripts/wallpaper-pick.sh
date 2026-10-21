#!/usr/bin/env bash
#
# wallpaper-pick.sh — kies een wallpaper uit een galerij met thumbnails
#                     (rofi) en pas daarna automatisch het thema aan.
#
# Gebonden aan Super+W.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/hypr-env.sh"

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/.local/share/wallpapers}"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/thumbs"
mkdir -p "${THUMB_DIR}"

if command -v magick >/dev/null 2>&1; then
    IM=magick
else
    IM=convert
fi

shopt -s nullglob
imgs=()
for f in "${WALLPAPER_DIR}"/*; do
    case "${f,,}" in
        *.jpg|*.jpeg|*.png|*.webp|*.bmp) imgs+=("${f}") ;;
    esac
done
shopt -u nullglob

if [[ ${#imgs[@]} -eq 0 ]]; then
    notify-send "Wallpaper" "Geen afbeeldingen gevonden in ${WALLPAPER_DIR}" 2>/dev/null || true
    exit 1
fi

choice=""
if command -v rofi >/dev/null 2>&1; then
    # rofi toont een thumbnail per regel ("naam\0icon\x1f<pad>").
    choice="$(
        for img in "${imgs[@]}"; do
            base="$(basename "${img}")"
            thumb="${THUMB_DIR}/${base}.png"
            if [[ ! -f "${thumb}" || "${img}" -nt "${thumb}" ]]; then
                "${IM}" "${img}" -thumbnail '512x288^' -gravity center -extent 512x288 \
                    "${thumb}" 2>/dev/null || thumb="${img}"
            fi
            printf '%s\0icon\x1f%s\n' "${base}" "${thumb}"
        done | rofi -dmenu -i -p 'Wallpaper' -show-icons \
            -theme-str 'element-icon { size: 8em; } listview { lines: 4; }'
    )" || exit 0
else
    # Fallback zonder thumbnails.
    choice="$(for img in "${imgs[@]}"; do basename "${img}"; done \
        | wofi --dmenu --prompt "Wallpaper" --width 600 --height 400)" || exit 0
fi

[[ -z "${choice}" ]] && exit 0

"${SCRIPT_DIR}/set-wallpaper.sh" "${WALLPAPER_DIR}/${choice}"
notify-send -i "${WALLPAPER_DIR}/${choice}" "Wallpaper" "Thema aangepast op $(basename "${choice}")" 2>/dev/null || true
