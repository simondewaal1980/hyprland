#!/usr/bin/env bash
#
# power-menu.sh — compacte power-menu (Super+Escape).
#
# wlogout rekt zijn knoppen standaard uit over het hele scherm. Door de
# marges op basis van de actieve monitor te berekenen, blijft het menu een
# gecentreerde rij van vijf kaarten op elke resolutie.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/hypr-env.sh"

readonly BUTTONS=5
readonly CARD_W=200
readonly CARD_H=96
readonly GAP=12
readonly EDGE=24

screen_w=1920
screen_h=1080

if command -v hyprctl >/dev/null 2>&1; then
    geometry="$(
        hyprctl monitors -j 2>/dev/null | python3 -c '
import json, sys

monitors = json.load(sys.stdin)
if not monitors:
    raise SystemExit(1)

monitor = next((m for m in monitors if m.get("focused")), monitors[0])
scale = float(monitor.get("scale") or 1)
print(round(monitor["width"] / scale), round(monitor["height"] / scale))
' 2>/dev/null || true
    )"

    if [[ "${geometry}" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
        screen_w="${BASH_REMATCH[1]}"
        screen_h="${BASH_REMATCH[2]}"
    fi
fi

row_width=$(( BUTTONS * CARD_W + (BUTTONS - 1) * GAP ))
side_margin=$(( (screen_w - row_width) / 2 ))
top_margin=$(( (screen_h - CARD_H) / 2 ))

if (( side_margin < EDGE )); then
    side_margin=${EDGE}
fi
if (( top_margin < EDGE )); then
    top_margin=${EDGE}
fi

exec wlogout --protocol layer-shell --buttons-per-row "${BUTTONS}" \
    --column-spacing "${GAP}" --row-spacing 0 \
    --margin-left "${side_margin}" --margin-right "${side_margin}" \
    --margin-top "${top_margin}" --margin-bottom "${top_margin}"
