#!/usr/bin/env bash
#
# apply-gtk-theme.sh — past het door pywal gegenereerde kleurenschema toe op
#                      GTK3- en GTK4-apps.
#
#   * schrijft ~/.cache/wal/gtk-colors.css (de kleuren)
#   * laat ~/.config/gtk-{3,4}.0/gtk.css dat bestand importeren
#   * zet GTK3/GTK4 op de donkere Breeze-variant en kleurschema 'prefer-dark'
#
# Het Breeze-GTK-thema gebruikt intern kleurnamen met het achtervoegsel
# '_breeze'. Alleen de standaard GTK-kleuren overschrijven is daarom niet
# genoeg: beide sets worden hieronder uit het pywal-palet gezet.
#
# Wordt automatisch aangeroepen door set-wallpaper.sh.
#
set -euo pipefail

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
COLORS_JSON="${WAL_CACHE}/colors.json"

if [[ ! -f "${COLORS_JSON}" ]]; then
    echo "apply-gtk-theme: ${COLORS_JSON} ontbreekt (draai eerst 'wal')." >&2
    exit 1
fi

python3 - "${COLORS_JSON}" "${WAL_CACHE}/gtk-colors.css" <<'PY'
"""Genereer GTK-kleuren uit het pywal-palet.

Breeze-Dark levert de donkere basis; dit bestand vervangt de kleuren door
de kleuren uit de wallpaper. Zowel de gewone GTK-namen als de '_breeze'-
varianten en de libadwaita-namen worden gezet.
"""

import colorsys
import json
import sys

src, dst = sys.argv[1], sys.argv[2]

with open(src, encoding="utf-8") as fh:
    data = json.load(fh)


def parse_hex(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in rgb)


def mix(a, b, t):
    """Meng kleur a met b; t=0 geeft a, t=1 geeft b."""
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def luminance(rgb):
    def channel(value):
        value = value / 255.0
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def best_fg(background, preferred):
    """Kies een leesbare voorgrondkleur op de opgegeven achtergrond."""
    if contrast(background, preferred) >= 4.5:
        return preferred
    white, black = (255, 255, 255), (0, 0, 0)
    return white if contrast(background, white) >= contrast(background, black) else black


special = data["special"]
palette = data["colors"]

background = parse_hex(special["background"])
foreground = parse_hex(special["foreground"])
colors = {name: parse_hex(value) for name, value in palette.items()}

# Ook bij een lichte wallpaper blijft het GTK-thema donker.
if luminance(background) > 0.25:
    hue, saturation, _ = colorsys.rgb_to_hsv(*(c / 255 for c in background))
    background = tuple(
        round(c * 255)
        for c in colorsys.hsv_to_rgb(hue, min(saturation, 0.65), 0.12)
    )
if contrast(background, foreground) < 4.5:
    foreground = best_fg(background, colors["color15"])

base = (
    colors["color0"]
    if luminance(colors["color0"]) <= luminance(background) + 0.02
    else mix(background, (0, 0, 0), 0.25)
)
background_alt = mix(background, foreground, 0.06)
button = mix(background, foreground, 0.10)
border = mix(background, foreground, 0.25)
muted = mix(background, foreground, 0.55)
insensitive_bg = mix(background, foreground, 0.04)
insensitive_fg = mix(background, foreground, 0.45)
insensitive_base = mix(base, foreground, 0.10)
accent = colors["color2"]
accent_fg = best_fg(accent, foreground)
link = colors["color4"]
visited = colors["color5"]
negative = colors["color1"]
neutral = colors["color3"]
positive = colors["color2"]
warning = colors["color3"]
error = colors["color1"]
success = colors["color2"]
insensitive_selected_bg = mix(insensitive_bg, accent, 0.35)
insensitive_selected_fg = mix(accent, accent_fg, 0.55)
unfocused_selected_bg = mix(accent, background, 0.50)
unfocused_selected_fg = accent_fg
insensitive_borders = mix(border, background, 0.55)
insensitive_warning = mix(warning, background, 0.55)
insensitive_error = mix(error, background, 0.55)
insensitive_success = mix(success, background, 0.55)


def define(name, color):
    return f"@define-color {name} {to_hex(color)};\n"


out = [
    "/* Automatisch gegenereerd uit de wallpaper (pywal). Niet handmatig aanpassen. */\n",
    "/* Basis: Breeze-Dark; de kleuren komen uit ~/.cache/wal/colors.json. */\n\n",
    "/* --- Breeze-GTK: intern gebruikte kleurnamen --- */\n",
]

breeze = [
    ("theme_fg_color_breeze", foreground),
    ("theme_text_color_breeze", foreground),
    ("theme_bg_color_breeze", background),
    ("theme_base_color_breeze", base),
    ("theme_view_hover_decoration_color_breeze", accent),
    ("theme_hovering_selected_bg_color_breeze", accent),
    ("theme_selected_bg_color_breeze", accent),
    ("theme_selected_fg_color_breeze", accent_fg),
    ("theme_view_active_decoration_color_breeze", accent),
    ("insensitive_selected_bg_color_breeze", insensitive_selected_bg),
    ("insensitive_bg_color_breeze", insensitive_bg),
    ("insensitive_fg_color_breeze", insensitive_fg),
    ("insensitive_base_color_breeze", insensitive_base),
    ("insensitive_base_fg_color_breeze", insensitive_fg),
    ("insensitive_selected_fg_color_breeze", insensitive_selected_fg),
    ("theme_unfocused_fg_color_breeze", foreground),
    ("theme_unfocused_text_color_breeze", foreground),
    ("theme_unfocused_bg_color_breeze", background),
    ("theme_unfocused_base_color_breeze", base),
    ("theme_unfocused_selected_bg_color_alt_breeze", accent),
    ("theme_unfocused_selected_bg_color_breeze", unfocused_selected_bg),
    ("theme_unfocused_selected_fg_color_breeze", unfocused_selected_fg),
    ("insensitive_unfocused_selected_bg_color_breeze", insensitive_selected_bg),
    ("insensitive_unfocused_fg_color_breeze", insensitive_fg),
    ("insensitive_unfocused_bg_color_breeze", insensitive_bg),
    ("insensitive_unfocused_selected_fg_color_breeze", insensitive_selected_fg),
    ("theme_unfocused_view_text_color_breeze", mix(base, foreground, 0.55)),
    ("theme_unfocused_view_bg_color_breeze", base),
    ("borders_breeze", border),
    ("borders_breeze_breeze", border),
    ("unfocused_borders_breeze", border),
    ("insensitive_borders_breeze", insensitive_borders),
    ("unfocused_insensitive_borders_breeze", insensitive_borders),
    ("unfocused_insensitive_color_breeze", insensitive_fg),
    ("theme_button_background_normal_breeze", button),
    ("theme_button_decoration_hover_breeze", accent),
    ("theme_button_decoration_focus_breeze", accent),
    ("theme_button_background_insensitive_breeze", mix(button, background, 0.55)),
    ("theme_button_decoration_hover_insensitive_breeze", mix(accent, background, 0.55)),
    ("theme_button_decoration_focus_insensitive_breeze", mix(accent, background, 0.55)),
    ("theme_button_foreground_insensitive_breeze", insensitive_fg),
    ("theme_button_foreground_active_insensitive_breeze", insensitive_fg),
    ("theme_button_background_backdrop_breeze", mix(button, background, 0.15)),
    ("theme_button_decoration_hover_backdrop_breeze", accent),
    ("theme_button_decoration_focus_backdrop_breeze", accent),
    ("theme_button_foreground_backdrop_breeze", foreground),
    ("theme_button_foreground_active_backdrop_breeze", foreground),
    ("theme_button_background_backdrop_insensitive_breeze", mix(button, background, 0.55)),
    ("theme_button_decoration_hover_backdrop_insensitive_breeze", mix(accent, background, 0.55)),
    ("theme_button_decoration_focus_backdrop_insensitive_breeze", mix(accent, background, 0.55)),
    ("theme_button_foreground_backdrop_insensitive_breeze", insensitive_fg),
    ("theme_button_foreground_active_backdrop_insensitive_breeze", insensitive_fg),
    ("warning_color_breeze", warning),
    ("error_color_breeze", error),
    ("success_color_breeze", success),
    ("warning_color_backdrop_breeze", warning),
    ("error_color_backdrop_breeze", error),
    ("success_color_backdrop_breeze", success),
    ("warning_color_insensitive_breeze", insensitive_warning),
    ("error_color_insensitive_breeze", insensitive_error),
    ("success_color_insensitive_breeze", insensitive_success),
    ("warning_color_insensitive_backdrop_breeze", insensitive_warning),
    ("error_color_insensitive_backdrop_breeze", insensitive_error),
    ("success_color_insensitive_backdrop_breeze", insensitive_success),
    ("link_color_breeze", link),
    ("link_visited_color_breeze", visited),
    ("theme_titlebar_background_breeze", background_alt),
    ("theme_titlebar_foreground_breeze", foreground),
    ("theme_titlebar_background_light_breeze", button),
    ("theme_titlebar_foreground_backdrop_breeze", muted),
    ("theme_titlebar_background_backdrop_breeze", background),
    ("theme_titlebar_foreground_insensitive_breeze", insensitive_fg),
    ("theme_titlebar_foreground_insensitive_backdrop_breeze", insensitive_fg),
    ("tooltip_text_breeze", foreground),
    ("tooltip_background_breeze", background_alt),
    ("tooltip_border_breeze", border),
    ("print_paper_backdrop_breeze", base),
    ("content_view_bg_breeze", base),
    ("theme_header_background_breeze", background_alt),
    ("theme_header_background_backdrop_breeze", background),
]

for name, color in breeze:
    out.append(define(name, color))

# Breeze gebruikt deze namen zonder '_breeze' ook rechtstreeks.
out.append(define("theme_button_foreground_normal_breeze", foreground))
out.append(define("theme_button_foreground_active_breeze", foreground))
out.append(define("theme_button_decoration_focus", accent))
out.append(define("theme_titlebar_background", background_alt))

out.append("\n/* --- Standaard GTK-kleurnamen --- */\n")
standard = [
    ("theme_fg_color", foreground),
    ("theme_text_color", foreground),
    ("theme_bg_color", background),
    ("theme_base_color", base),
    ("theme_selected_bg_color", accent),
    ("theme_selected_fg_color", accent_fg),
    ("insensitive_bg_color", insensitive_bg),
    ("insensitive_fg_color", insensitive_fg),
    ("insensitive_base_color", insensitive_base),
    ("theme_unfocused_fg_color", foreground),
    ("theme_unfocused_text_color", foreground),
    ("theme_unfocused_bg_color", background),
    ("theme_unfocused_base_color", base),
    ("theme_unfocused_selected_bg_color", unfocused_selected_bg),
    ("theme_unfocused_selected_fg_color", unfocused_selected_fg),
    ("unfocused_insensitive_color", insensitive_fg),
    ("borders", border),
    ("unfocused_borders", border),
    ("warning_color", warning),
    ("error_color", error),
    ("success_color", success),
    ("content_view_bg", base),
    ("text_view_bg", base),
]
for name, color in standard:
    out.append(define(name, color))

# libadwaita (GTK4) gebruikt weer andere namen. Ze helpen apps die het
# Adwaita-thema volgen in plaats van Breeze.
out.append("\n/* --- libadwaita / GTK4 --- */\n")
adwaita = [
    ("accent_color", accent),
    ("accent_bg_color", accent),
    ("accent_fg_color", accent_fg),
    ("window_bg_color", background),
    ("window_fg_color", foreground),
    ("view_bg_color", base),
    ("view_fg_color", foreground),
    ("headerbar_bg_color", background_alt),
    ("headerbar_fg_color", foreground),
    ("headerbar_backdrop_color", background),
    ("headerbar_shade_color", border),
    ("popover_bg_color", background_alt),
    ("popover_fg_color", foreground),
    ("card_bg_color", background_alt),
    ("card_fg_color", foreground),
    ("card_shade_color", border),
    ("dialog_bg_color", background_alt),
    ("dialog_fg_color", foreground),
    ("sidebar_bg_color", background),
    ("sidebar_fg_color", foreground),
    ("secondary_sidebar_bg_color", base),
    ("secondary_sidebar_fg_color", foreground),
    ("success_bg_color", success),
    ("success_fg_color", best_fg(success, foreground)),
    ("warning_bg_color", warning),
    ("warning_fg_color", best_fg(warning, foreground)),
    ("error_bg_color", error),
    ("error_fg_color", best_fg(error, foreground)),
    ("destructive_color", error),
    ("destructive_bg_color", error),
    ("destructive_fg_color", best_fg(error, foreground)),
]
for name, color in adwaita:
    out.append(define(name, color))

with open(dst, "w", encoding="utf-8") as fh:
    fh.writelines(out)
PY

GTK3_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0"
GTK4_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0"
mkdir -p "${GTK3_DIR}" "${GTK4_DIR}"

for dir in "${GTK3_DIR}" "${GTK4_DIR}"; do
    cat > "${dir}/gtk.css" <<EOF
/* Laadt de kleuren uit de wallpaper. Aanpassen doe je via pywal, niet hier. */
@import url("file://${WAL_CACHE}/gtk-colors.css");
EOF
done

# Kies de donkere Breeze-variant; val terug op Adwaita-dark als Breeze-GTK
# niet geïnstalleerd is.
gtk_theme="Breeze-Dark"
if [[ ! -d /usr/share/themes/Breeze-Dark ]]; then
    gtk_theme="Adwaita-dark"
fi

set_ini_key() {
    local file="$1" key="$2" value="$3"
    touch "${file}"
    if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${file}"; then
        sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key}=${value}|" "${file}"
    elif grep -q '^\[Settings\]' "${file}"; then
        sed -i "/^\[Settings\]/a ${key}=${value}" "${file}"
    else
        printf '[Settings]\n%s=%s\n' "${key}" "${value}" >> "${file}"
    fi
}

for dir in "${GTK3_DIR}" "${GTK4_DIR}"; do
    set_ini_key "${dir}/settings.ini" "gtk-theme-name" "${gtk_theme}"
    set_ini_key "${dir}/settings.ini" "gtk-application-prefer-dark-theme" "true"
done

# GTK2 (nog maar weinig gebruikt, maar het kost niets).
for rc in "${HOME}/.gtkrc-2.0" "${XDG_CONFIG_HOME:-$HOME/.config}/gtkrc-2.0"; do
    [[ -f "${rc}" ]] || continue
    if grep -q '^gtk-theme-name=' "${rc}"; then
        sed -i -E "s|^gtk-theme-name=.*|gtk-theme-name=\"${gtk_theme}\"|" "${rc}"
    else
        printf 'gtk-theme-name="%s"\n' "${gtk_theme}" >> "${rc}"
    fi
done

# Kleurschema 'prefer-dark' zodat ook libadwaita-apps (GNOME/GTK4) donker zijn.
if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "${gtk_theme}" 2>/dev/null || true
fi
