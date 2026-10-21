#!/usr/bin/env bash
#
# lock.sh — vergrendel het scherm (Super+L).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/hypr-env.sh"

if ! pgrep -x hyprlock >/dev/null 2>&1; then
    exec hyprlock
fi
