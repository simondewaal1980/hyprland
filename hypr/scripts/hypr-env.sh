#!/usr/bin/env bash
#
# hypr-env.sh — zet PATH en de Hyprland-omgevingsvariabelen goed.
# Wordt gesourced door de scripts die ook vanuit een systemd-user-service
# kunnen draaien (waar HYPRLAND_INSTANCE_SIGNATURE soms ontbreekt).
#
set -u

export PATH="${HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    # Hyprland bewaart zijn sockets tegenwoordig in $XDG_RUNTIME_DIR/hypr;
    # oudere versies gebruikten /tmp/hypr. Kies de nieuwste.
    for base in "${XDG_RUNTIME_DIR}/hypr" "/tmp/hypr"; do
        [[ -d "${base}" ]] || continue
        while IFS= read -r dir; do
            [[ -S "${dir}.socket.sock" ]] || continue
            export HYPRLAND_INSTANCE_SIGNATURE="$(basename "${dir}")"
            break 2
        done < <(ls -td "${base}"/*/ 2>/dev/null)
    done
fi
