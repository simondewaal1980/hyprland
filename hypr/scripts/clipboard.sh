#!/usr/bin/env bash
#
# clipboard.sh — klembordgeschiedenis tonen in wofi (Super+V).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/hypr-env.sh"

command -v cliphist >/dev/null 2>&1 || exit 0

# Wis-item bovenaan, zodat de geschiedenis leeg te maken is.
choice="$(
    {
        printf 'Wis geschiedenis\n'
        cliphist list
    } | wofi --dmenu --prompt "Klembord" --width 720 --height 480 --cache-file /dev/null
)" || exit 0

[[ -z "${choice}" ]] && exit 0

if [[ "${choice}" == "Wis geschiedenis" ]]; then
    cliphist wipe
    notify-send "Klembord" "Geschiedenis gewist" 2>/dev/null || true
    exit 0
fi

printf '%s\n' "${choice}" | cliphist decode | wl-copy
