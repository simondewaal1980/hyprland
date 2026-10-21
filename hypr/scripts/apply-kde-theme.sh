#!/usr/bin/env bash
#
# apply-kde-theme.sh — laat KDE- en Qt-apps het pywal-kleurenschema volgen.
#
#   * genereert ~/.local/share/color-schemes/Pywal.colors uit het pywal-palet
#   * activeert dat schema (plasma-apply-colorscheme, of anders kwriteconfig)
#   * zet de Breeze-widgetstijl, zodat Qt-apps ook buiten Plasma dezelfde
#     uitstraling hebben
#
# De Qt-apps lezen dit via de KDE-platformthema-plugin. Die plugin wordt
# geactiveerd met QT_QPA_PLATFORMTHEME=kde (zie config.py en ~/.profile).
#
# Wordt automatisch aangeroepen door set-wallpaper.sh.
#
set -euo pipefail

WAL_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/wal"
COLORS_JSON="${WAL_CACHE}/colors.json"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
SCHEME_DIR="${DATA_HOME}/color-schemes"
SCHEME_FILE="${SCHEME_DIR}/Pywal.colors"

if [[ ! -f "${COLORS_JSON}" ]]; then
    echo "apply-kde-theme: ${COLORS_JSON} ontbreekt (draai eerst 'wal')." >&2
    exit 1
fi

mkdir -p "${SCHEME_DIR}"

python3 - "${COLORS_JSON}" "${SCHEME_FILE}" <<'PY'
"""Genereer een KDE-kleurenschema (.colors) uit het pywal-palet."""

import colorsys
import json
import sys

src, dst = sys.argv[1], sys.argv[2]

with open(src, encoding="utf-8") as fh:
    data = json.load(fh)


def parse_hex(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
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
    if contrast(background, preferred) >= 4.5:
        return preferred
    white, black = (255, 255, 255), (0, 0, 0)
    return white if contrast(background, white) >= contrast(background, black) else black


def rgb(value):
    return ",".join(str(max(0, min(255, round(c)))) for c in value)


special = data["special"]
palette = data["colors"]
background = parse_hex(special["background"])
foreground = parse_hex(special["foreground"])
colors = {name: parse_hex(value) for name, value in palette.items()}

# Zorg dat het schema ook bij een lichte wallpaper donker blijft.
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
muted = mix(background, foreground, 0.55)
accent = colors["color2"]
accent_fg = best_fg(accent, foreground)
link = colors["color4"]
visited = colors["color5"]
negative = colors["color1"]
neutral = colors["color3"]
positive = colors["color2"]


def section(name, background, alternate, foreground, selection=False):
    if selection:
        normal = accent_fg
        inactive = mix(accent, accent_fg, 0.55)
        link_fg = accent_fg
        visited_fg = mix(accent, accent_fg, 0.70)
        negative_fg = mix(accent, (0, 0, 0), 0.55)
        neutral_fg = mix(accent, (0, 0, 0), 0.40)
        positive_fg = mix(accent, (0, 0, 0), 0.55)
    else:
        normal = foreground
        inactive = muted
        link_fg = link
        visited_fg = visited
        negative_fg = negative
        neutral_fg = neutral
        positive_fg = positive

    return f"""[{name}]
BackgroundAlternate={rgb(alternate)}
BackgroundNormal={rgb(background)}
DecorationFocus={rgb(accent)}
DecorationHover={rgb(accent)}
ForegroundActive={rgb(link_fg)}
ForegroundInactive={rgb(inactive)}
ForegroundLink={rgb(link_fg)}
ForegroundNegative={rgb(negative_fg)}
ForegroundNeutral={rgb(neutral_fg)}
ForegroundNormal={rgb(normal)}
ForegroundPositive={rgb(positive_fg)}
ForegroundVisited={rgb(visited_fg)}
"""


scheme = """[ColorEffects:Disabled]
Color=56,56,56
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
ChangeSelectionColor=true
Color=112,111,110
ColorAmount=0.025
ColorEffect=2
ContrastAmount=0.1
ContrastEffect=2
Enable=false
IntensityAmount=0
IntensityEffect=0

"""
scheme += section("Colors:Button", button, background_alt, foreground)
scheme += section("Colors:Complementary", background_alt, background, foreground)
scheme += section("Colors:Header", background_alt, background, foreground)
scheme += section("Colors:Header][Inactive", background, background_alt, foreground)
scheme += section(
    "Colors:Selection",
    accent,
    mix(accent, background, 0.20),
    accent_fg,
    selection=True,
)
scheme += section("Colors:Tooltip", background_alt, background, foreground)
scheme += section("Colors:View", base, background_alt, foreground)
scheme += section("Colors:Window", background, background_alt, foreground)
scheme += f"""[General]
Name=Pywal
shadeSortColumn=true

[KDE]
contrast=4

[WM]
activeBackground={rgb(background_alt)}
activeBlend={rgb(foreground)}
activeForeground={rgb(foreground)}
inactiveBackground={rgb(background)}
inactiveBlend={rgb(muted)}
inactiveForeground={rgb(muted)}
"""

with open(dst, "w", encoding="utf-8") as fh:
    fh.write(scheme)
PY

# Activeren. plasma-apply-colorscheme schrijft het schema naar kdeglobals en
# stuurt een signaal naar draaiende KDE-apps. Ontbreekt het hulpmiddel (bijv.
# op een minimale Arch-installatie), dan schrijven we de sleutels zelf.
KWRITE="$(command -v kwriteconfig6 || command -v kwriteconfig5 || true)"
applied=false

if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    # plasma-apply-colorscheme doet niets als ColorScheme al 'Pywal' is, ook
    # niet als het schema-bestand intussen is veranderd (bijvoorbeeld door een
    # nieuwe wallpaper). Daarom de huidige keuze eerst leegmaken.
    if [[ -n "${KWRITE}" ]]; then
        "${KWRITE}" --file kdeglobals --group General --key ColorScheme ""
    fi
    if plasma-apply-colorscheme Pywal >/dev/null 2>&1; then
        applied=true
    fi
fi

if [[ -n "${KWRITE}" ]]; then
    if ! ${applied}; then
        while IFS=$'\t' read -r group key value; do
            case "${group}" in
                Colors:*|WM|KDE) ;;
                *) continue ;;
            esac
            "${KWRITE}" --file kdeglobals --group "${group}" --key "${key}" "${value}"
        done < <(
            awk '
                /^\[/ {
                    group = substr($0, 2, length($0) - 2)
                    next
                }
                /^[A-Za-z][A-Za-z0-9_]*=/ {
                    key = $0
                    sub(/=.*/, "", key)
                    value = $0
                    sub(/^[^=]*=/, "", value)
                    print group "\t" key "\t" value
                }
            ' "${SCHEME_FILE}"
        )
    fi

    # Breeze-widgetstijl en het actieve schema ook expliciet in kdeglobals.
    "${KWRITE}" --file kdeglobals --group General --key ColorScheme Pywal
    "${KWRITE}" --file kdeglobals --group KDE --key widgetStyle Breeze
fi

if ! ${applied} && [[ -z "${KWRITE}" ]]; then
    echo "apply-kde-theme: geen plasma-apply-colorscheme of kwriteconfig gevonden;" >&2
    echo "                  het schema staat wel in ${SCHEME_FILE}." >&2
fi
