#!/usr/bin/env python3
"""Genereer alle themabestanden uit het pywal-palet van de wallpaper.

Aangeroepen door set-wallpaper.sh, nadat `wal` een nieuw palet heeft
gemaakt. Schrijft kleuren voor Hyprland, Waybar, wofi, wlogout, mako,
kitty, Hyprlock en OpenCode. De basis blijft donker, ook bij een lichte
wallpaper.
"""

from __future__ import annotations

import colorsys
import json
import os
import shutil
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


def hue_scale(anchor, bg) -> dict[str, str]:
    """Maak de negen stappen van een OpenCode-hue (donker thema)."""
    return {
        "100": to_hex(mix(anchor, WHITE, 0.48)),
        "200": to_hex(anchor),
        "300": to_hex(mix(anchor, bg, 0.18)),
        "400": to_hex(mix(anchor, bg, 0.34)),
        "500": to_hex(mix(anchor, bg, 0.50)),
        "600": to_hex(mix(anchor, bg, 0.65)),
        "700": to_hex(mix(anchor, bg, 0.78)),
        "800": to_hex(mix(anchor, bg, 0.88)),
        "900": to_hex(mix(anchor, bg, 0.94)),
    }


def wallpaper_hue(color, fallback, bg):
    """Gebruik een paletkleur als hij genoeg kleur en contrast heeft."""
    if color is None or saturation(color) < 0.16 or contrast(bg, color) < 1.8:
        color = fallback
    return readable_on(bg, color, 3.2)


def nearest_hue(color, anchors: dict) -> str:
    return min(
        anchors,
        key=lambda name: hue_distance(hue(color), hue(anchors[name])),
    )


def write_opencode_theme(
    *,
    bg,
    fg,
    muted,
    outline,
    surface,
    surface2,
    surface3,
    primary,
    secondary,
    tertiary,
    source_colors: dict,
) -> None:
    """Schrijf ~/.config/opencode/themes/wal.json uit het pywal-palet.

    OpenCode leest zijn thema's bij het starten; een draaiende sessie pakt de
    nieuwe kleuren dus pas na een herstart op.
    """
    theme_dir = CONFIG / "opencode" / "themes"
    theme_dir.mkdir(parents=True, exist_ok=True)

    # Vaste semantische tinten blijven herkenbaar; blauw, cyaan en paars
    # komen bij voorkeur uit de wallpaper zelf.
    anchors = {
        "red": ERROR,
        "orange": mix(ERROR, WARNING, 0.62),
        "yellow": WARNING,
        "green": SUCCESS,
        "cyan": wallpaper_hue(source_colors.get("color6"), (118, 196, 220), bg),
        "blue": wallpaper_hue(source_colors.get("color4"), (110, 165, 235), bg),
        "purple": wallpaper_hue(source_colors.get("color5"), (190, 145, 230), bg),
    }

    # Laat accent en interactieve kleur precies bij de gekozen
    # wallpaper-accenten aansluiten.
    families = tuple(anchors)
    primary_family = nearest_hue(primary, anchors)
    anchors[primary_family] = primary
    secondary_family = min(
        (name for name in families if name != primary_family),
        key=lambda name: hue_distance(hue(secondary), hue(anchors[name])),
    )
    anchors[secondary_family] = secondary
    tertiary_family = nearest_hue(tertiary, anchors)
    if tertiary_family not in (primary_family, secondary_family):
        anchors[tertiary_family] = tertiary

    hues = {
        "gray": {
            "100": to_hex(mix(fg, WHITE, 0.45)),
            "200": to_hex(fg),
            "300": to_hex(mix(bg, fg, 0.78)),
            "400": to_hex(muted),
            "500": to_hex(mix(bg, fg, 0.40)),
            "600": to_hex(surface3),
            "700": to_hex(surface2),
            "800": to_hex(surface),
            "900": to_hex(bg),
        }
    }
    for name, anchor in anchors.items():
        hues[name] = hue_scale(anchor, bg)
    hues["accent"] = f"$hue.{primary_family}"
    hues["interactive"] = f"$hue.{secondary_family}"
    hues["neutral"] = "$hue.gray"

    categorical = []
    for name in (primary_family, secondary_family, "green", "cyan", "red"):
        if name not in categorical:
            categorical.append(name)

    theme = {
        "$schema": "https://opencode.ai/theme.json",
        "base": {
            "categorical": categorical,
            "text": {
                "base": "$hue.neutral.200",
                "muted": "$hue.neutral.400",
                "action": {
                    "primary": {
                        "base": "$hue.accent.200",
                        "$disabled": "$hue.neutral.500",
                        "$focused": "$hue.neutral.900",
                        "$selected": "$hue.interactive.200",
                    },
                    "secondary": {
                        "base": "$text.muted",
                        "$hovered": "$text.base",
                    },
                    "destructive": {
                        "base": "$hue.neutral.900",
                        "$disabled": "$hue.neutral.500",
                    },
                },
                "formfield": {
                    "base": "$hue.neutral.200",
                    "$hovered": "$hue.interactive.200",
                    "$focused": "$hue.interactive.200",
                    "$pressed": "$hue.interactive.200",
                    "$disabled": "$hue.neutral.500",
                    "$selected": "$hue.interactive.200",
                },
                "feedback": {
                    "error": {"base": to_hex(ERROR)},
                    "warning": {"base": to_hex(WARNING)},
                    "success": {"base": to_hex(SUCCESS)},
                    "info": {"base": "$hue.cyan.200"},
                },
            },
            "background": {
                "base": "$hue.neutral.900",
                "raised": {
                    "base": "$hue.neutral.800",
                    "high": "$hue.neutral.700",
                    "max": "$hue.neutral.600",
                },
                "action": {
                    "primary": {
                        "base": "transparent",
                        "$hovered": "$hue.neutral.800",
                        "$focused": "$hue.interactive.200",
                        "$selected": "transparent",
                    },
                    "secondary": {
                        "base": "transparent",
                        "$hovered": "$hue.neutral.800",
                    },
                    "destructive": {"base": to_hex(ERROR)},
                },
                "formfield": {"base": "$background.base"},
                "feedback": {
                    "error": {"base": "$background.base"},
                    "warning": {"base": "$background.base"},
                    "success": {"base": "$background.base"},
                    "info": {"base": "$background.base"},
                },
            },
            "border": {"base": to_hex(outline)},
            "scrollbar": {"base": to_hex(mix(outline, fg, 0.28))},
            "diff": {
                "text": {
                    "added": to_hex(SUCCESS),
                    "removed": to_hex(ERROR),
                    "context": "$hue.neutral.400",
                    "hunkHeader": "$hue.neutral.400",
                },
                "background": {
                    "added": "$hue.green.900",
                    "removed": "$hue.red.900",
                    "context": "$hue.neutral.800",
                },
                "highlight": {
                    "added": "$hue.green.100",
                    "removed": "$hue.red.100",
                },
                "lineNumber": {
                    "text": "$hue.neutral.400",
                    "background": {
                        "added": to_hex(mix(bg, SUCCESS, 0.08)),
                        "removed": to_hex(mix(bg, ERROR, 0.08)),
                    },
                },
            },
            "syntax": {
                "comment": "$hue.neutral.400",
                "keyword": "$hue.accent.200",
                "function": "$hue.interactive.200",
                "variable": "$hue.red.200",
                "string": "$hue.green.200",
                "number": "$hue.orange.100",
                "type": "$hue.cyan.100",
                "operator": "$hue.cyan.200",
                "punctuation": "$hue.neutral.200",
            },
            "markdown": {
                "text": "$hue.neutral.200",
                "heading": "$hue.accent.200",
                "link": "$hue.interactive.200",
                "linkText": "$hue.cyan.200",
                "code": "$hue.green.200",
                "blockQuote": "$hue.orange.100",
                "emphasis": "$hue.orange.100",
                "strong": "$hue.orange.200",
                "horizontalRule": "$hue.neutral.400",
                "listItem": "$hue.interactive.200",
                "listEnumeration": "$hue.cyan.200",
                "image": "$hue.interactive.200",
                "imageText": "$hue.cyan.200",
                "codeBlock": "$hue.neutral.200",
            },
            "@dialog": {
                "background": {
                    "base": "$background.raised.base",
                    "action": {
                        "primary": {
                            "$hovered": "$background.raised.high",
                        }
                    },
                }
            },
        },
        "dark": {"hue": hues},
    }

    (theme_dir / "wal.json").write_text(
        json.dumps(theme, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )



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

    # --- OpenCode ---------------------------------------------------------
    # Alleen schrijven als OpenCode hier gebruikt wordt; de themanaam 'wal'
    # staat in ~/.config/opencode/cli.json (zie install.sh).
    if (CONFIG / "opencode").exists() or shutil.which("opencode"):
        write_opencode_theme(
            bg=bg,
            fg=fg,
            muted=muted,
            outline=outline,
            surface=surface,
            surface2=surface2,
            surface3=surface3,
            primary=primary,
            secondary=secondary,
            tertiary=tertiary,
            source_colors=base_colors,
        )

    # --- Overige apps / scripts ------------------------------------------
    (CACHE / "hypr" / "palette.json").write_text(
        json.dumps(palette, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (CACHE / "hypr" / "current-wallpaper").write_text(str(wallpaper) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
