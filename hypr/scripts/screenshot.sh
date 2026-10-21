#!/usr/bin/env bash
#
# screenshot.sh — schermafdruk maken, opslaan en naar het klembord kopiëren.
#
# Gebruik:
#   screenshot.sh full     — hele scherm (Print)
#   screenshot.sh region   — selectie met slurp (Super+Print)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/hypr-env.sh"

mode="${1:-full}"
dir="${HOME}/Pictures/Screenshots"
mkdir -p "${dir}"
file="${dir}/$(date '+%Y-%m-%d_%H-%M-%S').png"

case "${mode}" in
    full)
        grim "${file}"
        ;;
    region)
        geometry="$(slurp -b '#00000055' -c '#ffffffff' -w 2)" || exit 0
        [[ -n "${geometry}" ]] || exit 0
        grim -g "${geometry}" "${file}"
        ;;
    *)
        echo "screenshot: onbekende modus '${mode}'" >&2
        exit 1
        ;;
esac

[[ -s "${file}" ]] || exit 1

wl-copy < "${file}"
notify-send -i "${file}" "Schermafdruk opgeslagen" "$(basename "${file}")" 2>/dev/null || true
