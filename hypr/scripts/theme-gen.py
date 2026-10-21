#!/usr/bin/env python3
"""Genereer alle themabestanden uit het pywal-palet van de wallpaper.

Aangeroepen door set-wallpaper.sh, nadat `wal` een nieuw palet heeft
gemaakt. Schrijft kleuren voor Hyprland, Waybar, wofi, wlogout, mako,
kitty en Hyprlock. De basis blijft donker, ook bij een lichte wallpaper.
"""

from __future__ import annotations

import colorsys
import json
import os
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))
WAL_JSON = CACHE / "wal" / "colors.json"

# Vaste semantische kleuren: rood/groen/geel moeten herkenbaar blijven,
# ongeacht de wallpaper. Ze zijn zacht genoeg voor een donkere bar.
ERROR = (255, 122, 133)
WARNING = (245, 201, 123)
SUCCESS = (143, 214, 148)
BLACK = (12, 12, 12)
WHITE = (245, 245, 245)


def parse_hex(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def to_hex(rgb: tuple[float, float, float]) -> str:
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(c))) for c in rgb)


def to_rgba(rgb: tuple[float, float, float], alpha: float = 1.0) -> str:
    r, g, b = (max(0, min(255, round(c))) for c in rgb)
    return f"rgba({r},{g},{b},{alpha:.2f})"


def mix(a, b, t: float):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def luminance(rgb) -> float:
    def channel(value: float) -> float:
        value /= 255.0
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b) -> float:
    la, lb = luminance(a), luminance(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def saturation(rgb) -> float:
    return colorsys.rgb_to_hsv(*(c / 255 for c in rgb))[1]


def hue(rgb) -> float:
    return colorsys.rgb_to_hsv(*(c / 255 for c in rgb))[0]


def hue_distance(a: float, b: float) -> float:
    d = abs(a - b) % 1.0
    return min(d, 1.0 - d)


def best_foreground(background) -> tuple[int, int, int]:
    return BLACK if contrast(background, BLACK) >= contrast(background, WHITE) else WHITE


def readable_on(background, color, target: float = 4.0):
    """Maak een accent lichter tot het leesbaar is op de donkere achtergrond."""
    for _ in range(24):
        if contrast(background, color) >= target:
            break
        color = mix(color, WHITE, 0.07)
    return color


def load_palette() -> dict:
    with WAL_JSON.open(encoding="utf-8") as fh:
        return json.load(fh)


def main() -> int:
    if not WAL_JSON.exists():
        print(f"theme-gen: {WAL_JSON} ontbreekt; draai eerst wal.", file=sys.stderr)
        return 1

    data = load_palette()
    wallpaper = sys.argv[1] if len(sys.argv) > 1 else data.get("wallpaper", "")
    special = data["special"]
    base_colors = {k: parse_hex(v) for k, v in data["colors"].items()}

    bg = parse_hex(special["background"])
    fg = parse_hex(special["foreground"])

    # Forceer een donkere achtergrond, ook als de foto heel licht is.
    if luminance(bg) > 0.085:
        h, s, _ = colorsys.rgb_to_hsv(*(c / 255 for c in bg))
        bg = tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, min(s, 0.55), 0.075))

    if contrast(bg, fg) < 6.0:
        fg = mix(WHITE, base_colors.get("color7", WHITE), 0.25)
    fg = readable_on(bg, fg, 7.0)

    surface = mix(bg, fg, 0.055)
    surface2 = mix(bg, fg, 0.095)
    surface3 = mix(bg, fg, 0.145)
    outline = mix(bg, fg, 0.24)
    muted = mix(bg, fg, 0.58)

    # Kies het meest bruikbare, verzadigde paletaccent.
    candidates = [
        base_colors.get(f"color{i}", fg)
        for i in (2, 4, 6, 3, 5, 1, 9, 10, 12, 13, 14)
    ]

    def accent_score(color) -> float:
        return saturation(color) * (0.6 + min(contrast(bg, color), 8.0))

    primary = max(candidates, key=accent_score)
    if saturation(primary) < 0.22 or contrast(bg, primary) < 2.0:
        h, s, _ = colorsys.rgb_to_hsv(*(c / 255 for c in bg))
        primary = tuple(
            round(c * 255)
            for c in colorsys.hsv_to_rgb((h + 0.48) % 1.0, 0.52, 0.74)
        )
    primary = readable_on(bg, primary, 4.0)

    # Een tweede accent met een andere tint, anders een afgeleide variant.
    rest = [
        c
        for c in candidates
        if hue_distance(hue(c), hue(primary)) > 0.10 and saturation(c) > 0.18
    ]
    secondary = max(rest, key=accent_score) if rest else mix(primary, fg, 0.35)
    secondary = readable_on(bg, secondary, 3.6)

    tertiary = base_colors.get("color5", secondary)
    if saturation(tertiary) < 0.18:
        tertiary = mix(primary, secondary, 0.5)
    tertiary = readable_on(bg, tertiary, 3.2)

    on_primary = best_foreground(primary)
    on_secondary = best_foreground(secondary)
    on_error = best_foreground(ERROR)

    palette = {
        "wallpaper": str(wallpaper),
        "bg": to_hex(bg),
        "surface": to_hex(surface),
        "surface2": to_hex(surface2),
        "surface3": to_hex(surface3),
        "fg": to_hex(fg),
        "muted": to_hex(muted),
        "outline": to_hex(outline),
        "primary": to_hex(primary),
        "on_primary": to_hex(on_primary),
        "secondary": to_hex(secondary),
        "on_secondary": to_hex(on_secondary),
        "tertiary": to_hex(tertiary),
        "error": to_hex(ERROR),
        "on_error": to_hex(on_error),
        "warning": to_hex(WARNING),
        "success": to_hex(SUCCESS),
    }

    for directory in (
        CONFIG / "hypr",
        CONFIG / "waybar",
        CONFIG / "wofi",
        CONFIG / "wlogout",
        CONFIG / "mako",
        CONFIG / "kitty",
        CACHE / "hypr",
    ):
        directory.mkdir(parents=True, exist_ok=True)

    # --- Hyprland ---------------------------------------------------------
    hypr_colors = f"""# Automatisch gegenereerd uit {wallpaper}
# door ~/.config/hypr/scripts/theme-gen.py. Niet handmatig aanpassen.

$wallpaper = {wallpaper}

$bg = {to_rgba(bg)}
$surface = {to_rgba(surface)}
$surface_alt = {to_rgba(surface2)}
$surface_high = {to_rgba(surface3)}
$fg = {to_rgba(fg)}
$fg_muted = {to_rgba(muted)}
$primary = {to_rgba(primary)}
$on_primary = {to_rgba(on_primary)}
$secondary = {to_rgba(secondary)}
$tertiary = {to_rgba(tertiary)}
$outline = {to_rgba(outline)}
$error = {to_rgba(ERROR)}
$warning = {to_rgba(WARNING)}
$success = {to_rgba(SUCCESS)}
$shadow = rgba(0,0,0,0.35)
"""
    (CONFIG / "hypr" / "colors.conf").write_text(hypr_colors, encoding="utf-8")

    # --- Hyprlock (uit template) -----------------------------------------
    template = CONFIG / "hypr" / "hyprlock.template.conf"
    if template.exists():
        lock = template.read_text(encoding="utf-8")
        replacements = {
            "{{wallpaper}}": str(wallpaper),
            "{{primary}}": to_rgba(primary),
            "{{surface_glass}}": to_rgba(surface, 0.72),
            "{{fg}}": to_rgba(fg),
            "{{muted}}": to_rgba(muted),
            "{{success}}": to_rgba(SUCCESS),
            "{{error}}": to_rgba(ERROR),
        }
        for needle, value in replacements.items():
            lock = lock.replace(needle, value)
        (CONFIG / "hypr" / "hyprlock.conf").write_text(lock, encoding="utf-8")

    # --- Gedeelde GTK-CSS-kleuren (Waybar, wofi, wlogout) -----------------
    css = f"""/* Automatisch gegenereerd uit {wallpaper}. Niet aanpassen. */
@define-color bg {palette["bg"]};
@define-color surface {palette["surface"]};
@define-color surface2 {palette["surface2"]};
@define-color surface3 {palette["surface3"]};
@define-color fg {palette["fg"]};
@define-color muted {palette["muted"]};
@define-color outline {palette["outline"]};
@define-color primary {palette["primary"]};
@define-color on_primary {palette["on_primary"]};
@define-color secondary {palette["secondary"]};
@define-color on_secondary {palette["on_secondary"]};
@define-color tertiary {palette["tertiary"]};
@define-color error {palette["error"]};
@define-color on_error {palette["on_error"]};
@define-color warning {palette["warning"]};
@define-color success {palette["success"]};
@define-color shadow #000000;
"""
    for app in ("waybar", "wofi", "wlogout"):
        (CONFIG / app / "colors.css").write_text(css, encoding="utf-8")

    # --- Mako -------------------------------------------------------------
    def mako_hex(color: str, alpha: str = "") -> str:
        return color + alpha

    mako = f"""# Automatisch gegenereerd uit {wallpaper}. Niet aanpassen.
background-color={mako_hex(palette["bg"], "ee")}
text-color={palette["fg"]}
border-color={palette["primary"]}
progress-color=over {mako_hex(palette["primary"], "55")}

[urgency=low]
border-color={palette["outline"]}
background-color={mako_hex(palette["surface"], "f2")}

[urgency=critical]
border-color={palette["error"]}
background-color={mako_hex(palette["surface"], "f2")}
text-color={palette["fg"]}
"""
    (CONFIG / "mako" / "colors").write_text(mako, encoding="utf-8")

    # --- Kitty ------------------------------------------------------------
    kitty = f"""# Automatisch gegenereerd uit {wallpaper}. Niet aanpassen.

font_family JetBrainsMono Nerd Font
font_size 11
window_padding_width 14
hide_window_decorations yes
confirm_os_window_close 0

foreground {palette["fg"]}
background {palette["bg"]}
background_opacity 0.94
dynamic_background_opacity yes

cursor {palette["primary"]}
cursor_text_color {palette["bg"]}
selection_background {palette["surface3"]}
selection_foreground {palette["fg"]}
url_color {palette["primary"]}

active_border_color {palette["primary"]}
inactive_border_color {palette["outline"]}
bell_border_color {palette["warning"]}
visual_bell_color {palette["error"]}

active_tab_background {palette["primary"]}
active_tab_foreground {palette["on_primary"]}
inactive_tab_background {palette["surface"]}
inactive_tab_foreground {palette["muted"]}
tab_bar_background {palette["bg"]}
tab_bar_style powerline
tab_powerline_style slanted

color0 {palette["bg"]}
color8 {palette["surface3"]}
color1 {palette["error"]}
color9 {palette["error"]}
color2 {palette["success"]}
color10 {palette["success"]}
color3 {palette["warning"]}
color11 {palette["warning"]}
color4 {palette["primary"]}
color12 {palette["primary"]}
color5 {palette["secondary"]}
color13 {palette["secondary"]}
color6 {palette["tertiary"]}
color14 {palette["tertiary"]}
color7 {palette["fg"]}
color15 {palette["fg"]}
"""
    (CONFIG / "kitty" / "hyprland-theme.conf").write_text(kitty, encoding="utf-8")

    # --- Overige apps / scripts ------------------------------------------
    (CACHE / "hypr" / "palette.json").write_text(
        json.dumps(palette, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (CACHE / "hypr" / "current-wallpaper").write_text(str(wallpaper) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
