#!/usr/bin/env bash
#
# set-wallpaper.sh — kies een wallpaper, genereer het kleurenschema met pywal
#                     en pas het toe op Hyprland, Waybar, wofi, wlogout,
#                     mako, kitty, Hyprlock, GTK- en Qt/KDE-apps.
#
# Gebruik:
#   set-wallpaper.sh [pad/naar/afbeelding]
#
# Zonder argument wordt de huidige wallpaper gebruikt (of de eerste foto in
# ~/.local/share/wallpapers).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/hypr-env.sh"

WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/.local/share/wallpapers}"
WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
HYPR_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"

img="${1:-}"

if [[ -z "${img}" ]]; then
    if [[ -f "${HYPR_CACHE}/current-wallpaper" ]]; then
        img="$(<"${HYPR_CACHE}/current-wallpaper")"
    elif [[ -f "${WAL_CACHE}/colors.json" ]]; then
        img="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wallpaper",""))' \
            "${WAL_CACHE}/colors.json" 2>/dev/null || true)"
    fi
fi

if [[ -z "${img}" || ! -f "${img}" ]]; then
    shopt -s nullglob
    candidates=(
        "${WALLPAPER_DIR}"/*.jpg "${WALLPAPER_DIR}"/*.jpeg
        "${WALLPAPER_DIR}"/*.png "${WALLPAPER_DIR}"/*.webp
    )
    shopt -u nullglob
    [[ ${#candidates[@]} -gt 0 ]] || {
        echo "set-wallpaper: geen wallpaper gevonden in ${WALLPAPER_DIR}" >&2
        exit 1
    }
    img="${candidates[0]}"
fi

img="$(readlink -f "${img}")"

if [[ ! -f "${img}" ]]; then
    echo "set-wallpaper: afbeelding niet gevonden: ${img}" >&2
    exit 1
fi

if ! command -v wal >/dev/null 2>&1; then
    echo "set-wallpaper: 'wal' (pywal16) niet gevonden; installeer met: pipx install pywal16" >&2
    exit 1
fi

# 1. Palet maken. -n betekent: zet de wallpaper niet zelf (dat doet hyprpaper).
# -e slaat pywal's eigen reload-hooks over. Die sturen een SIGUSR2 naar Waybar,
# waardoor die ~50 ms lang org.kde.StatusNotifierWatcher laat vallen; Spotify's
# CEF-tray kan daarvan in een D-Bus-abort belanden. Ook proberen ze kitty via
# een vaste socket te herladen die hier niet bestaat. De reloads die we echt
# nodig hebben, doen we in stap 4 zelf — precies één keer.
wal_log="$(mktemp)"
if ! wal -i "${img}" -n -q -e 2>"${wal_log}"; then
    cat "${wal_log}" >&2
    rm -f "${wal_log}"
    exit 1
fi
grep -v -e 'kitty_pywal' -e 'Failed to connect to unix' "${wal_log}" >&2 || true
rm -f "${wal_log}"

# 2. Alle themabestanden genereren (Hyprland, Waybar, wofi, mako, kitty, lock).
python3 "${SCRIPT_DIR}/theme-gen.py" "${img}"

# 3. Wallpaper zetten via hyprpaper, als Hyprland draait.
if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
    if ! pgrep -x hyprpaper >/dev/null 2>&1; then
        hyprpaper >/dev/null 2>&1 &
    fi

    # Wacht kort tot hyprpaper zijn IPC-socket heeft.
    for _ in $(seq 1 30); do
        hyprctl hyprpaper listloaded >/dev/null 2>&1 && break
        sleep 0.1
    done

    hyprctl hyprpaper unload all >/dev/null 2>&1 || true
    hyprctl hyprpaper preload "${img}" >/dev/null 2>&1 || true

    mapfile -t monitors < <(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null)
    for monitor in "${monitors[@]}"; do
        [[ -n "${monitor}" ]] || continue
        hyprctl hyprpaper wallpaper "${monitor},${img}" >/dev/null 2>&1 || true
    done

    # Hyprland opnieuw laten inlezen: nieuwe rand-, blur- en schaduwkleuren.
    hyprctl reload >/dev/null 2>&1 || true
fi

# 4. Draaiende apps herladen waar dat kan.
# Waybar heeft geen signaal nodig: reload_style_on_change volgt de @import in
# style.css en herlaadt colors.css dus zelf. Zo blijft de StatusNotifierWatcher
# van Waybar in leven en hoeft Spotify zijn tray-item niet opnieuw aan te melden.
# Alleen als die optie niet aan staat (of de config ontbreekt), sturen we SIGUSR2.
waybar_reloads_style=false
for waybar_conf in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config"; do
    if [[ -f "${waybar_conf}" ]] && \
        grep -qE '"reload_style_on_change"[[:space:]]*:[[:space:]]*true' "${waybar_conf}"; then
        waybar_reloads_style=true
    fi
done
if ! ${waybar_reloads_style}; then
    pkill -SIGUSR2 -x waybar 2>/dev/null || true
fi
# Xresources voor Xwayland-apps; met -e heeft pywal zijn eigen xrdb overgeslagen.
if command -v xrdb >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    xrdb -merge -quiet "${WAL_CACHE}/colors.Xresources" 2>/dev/null || true
fi
for pid in $(pgrep -x kitty 2>/dev/null || true); do
    kill -USR1 "${pid}" 2>/dev/null || true
done
if pgrep -x mako >/dev/null 2>&1; then
    makoctl reload >/dev/null 2>&1 || true
fi

# 5. GTK3/GTK4 en KDE/Qt-apps.
[[ -x "${SCRIPT_DIR}/apply-gtk-theme.sh" ]] && "${SCRIPT_DIR}/apply-gtk-theme.sh"
[[ -x "${SCRIPT_DIR}/apply-kde-theme.sh" ]] && "${SCRIPT_DIR}/apply-kde-theme.sh"

# 6. Rofi leest ~/.cache/wal/colors-rofi-dark.rasi automatisch bij de volgende start.

echo "set-wallpaper: $(basename "${img}")"
