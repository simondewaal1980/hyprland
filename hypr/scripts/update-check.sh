#!/usr/bin/env bash
#
# update-check.sh — Waybar-knop voor update.sh.
#
#   update-check.sh             status tonen (gecachet, maximaal een uur oud)
#   update-check.sh --refresh   nu controleren en de cache verversen
#   update-check.sh --run       update.sh in een terminal openen
#   update-check.sh --check     alleen controleren in een terminal
#
# De module geeft JSON terug (return-type "json"): een pictogram, een tooltip
# met de details en een CSS-class. Bij beschikbare updates komt er een aantal
# achter het pictogram en kleurt de knop waarschuwend.
#
set -u

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}"
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/hyprland-updates"
CACHE_FILE="${CACHE_DIR}/status.json"
CACHE_TTL=3600
SELF="$(readlink -f "$0")"

ICON=$'\uF019'       # download
ERROR_ICON=$'\uF071' # exclamation-triangle

usage() {
    cat <<EOF
Gebruik: $(basename "$0") [opties]

Zonder opties toont het script de status voor Waybar.

Opties:
  --refresh   nu controleren en de cache verversen
  --run       update.sh in een terminal openen
  --check     alleen controleren in een terminal
  -h, --help  deze uitleg tonen
EOF
}

# De configuraties worden naar ~/.config gekopieerd; install.sh bewaart daarbij
# het pad van deze repository in .repo-path, zodat update.sh vindbaar blijft.
repo_dir() {
    local candidate
    local path_file="${CONFIG_DIR}/hypr/.repo-path"
    local -a candidates=()

    [[ -n "${HYPRLAND_REPO:-}" ]] && candidates+=("${HYPRLAND_REPO}")
    if [[ -r "${path_file}" ]]; then
        candidates+=("$(head -n 1 "${path_file}")")
    fi
    candidates+=(
        "${HOME}/Projecten/Hyprland"
        "${HOME}/Hyprland"
        "${HOME}/.local/share/hyprland"
    )

    for candidate in "${candidates[@]}"; do
        [[ -n "${candidate}" ]] || continue
        if [[ -f "${candidate}/update.sh" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

emit() {
    local text="$1" tooltip="$2" class="$3" cache="${4:-yes}" json tmp

    json="$(jq -cn --arg text "${text}" --arg tooltip "${tooltip}" \
        --arg class "${class}" \
        '{text: $text, tooltip: $tooltip, class: $class}')" || return 1
    printf '%s\n' "${json}"

    if [[ "${cache}" == "yes" ]] && mkdir -p "${CACHE_DIR}" 2>/dev/null; then
        tmp="$(mktemp "${CACHE_DIR}/.status.XXXXXX" 2>/dev/null)" || return 0
        printf '%s\n' "${json}" > "${tmp}" && mv "${tmp}" "${CACHE_FILE}" \
            || rm -f "${tmp}"
    fi
}

refresh() {
    local repo output count details checked tooltip class

    repo="$(repo_dir || true)"
    if [[ -z "${repo}" ]]; then
        emit "${ERROR_ICON}" \
            "Hyprland-desktopopzet"$'\n'"Repository niet gevonden."$'\n'"Draai install.sh opnieuw vanuit de map van deze rice." \
            "unavailable" no
        return
    fi

    output="$("${repo}/update.sh" --check 2>&1 || true)"

    count="$(printf '%s\n' "${output}" \
        | sed -n 's/^>> \([0-9][0-9]*\) update(s) beschikbaar.*/\1/p' \
        | tail -n 1)"

    if [[ -z "${count}" ]]; then
        if grep -qx '>> Alles is bij\.' <<<"${output}"; then
            count=0
        else
            emit "${ERROR_ICON}" \
                "Hyprland-desktopopzet"$'\n'"Kon de update-status niet bepalen."$'\n\n'"${output}" \
                "unavailable" no
            return
        fi
    fi

    details="$(printf '%s\n' "${output}" \
        | grep -E '^>> (Ubuntu-pakketten|Flatpak|pywal16|Nerd Font|hyprlock):|^!! ' \
        | sed 's/^>> //')"
    checked="$(date '+%d-%m %H:%M')"

    if (( count > 0 )); then
        class="has-updates"
        tooltip="Hyprland-desktopopzet"$'\n'
        tooltip+="${count} update(s) beschikbaar"$'\n\n'
        tooltip+="${details}"$'\n\n'
        tooltip+="Laatst gecontroleerd: ${checked}"$'\n'
        tooltip+="Klik om bij te werken · rechtsklik om alleen te controleren"
        emit "${ICON}  ${count}" "${tooltip}" "${class}"
    else
        class="up-to-date"
        tooltip="Hyprland-desktopopzet"$'\n'
        tooltip+="Alles is bij."$'\n\n'
        tooltip+="${details}"$'\n\n'
        tooltip+="Laatst gecontroleerd: ${checked}"$'\n'
        tooltip+="Klik om bij te werken · rechtsklik om alleen te controleren"
        emit "${ICON}" "${tooltip}" "${class}"
    fi
}

open_terminal() {
    local mode="$1" repo

    repo="$(repo_dir || true)"
    if [[ -z "${repo}" ]]; then
        notify-send "Hyprland-desktopopzet" \
            "Repository niet gevonden. Draai install.sh opnieuw." \
            2>/dev/null || true
        return 1
    fi

    # Na het venster bepaalt de volgende Waybar-ronde de status opnieuw.
    rm -f "${CACHE_FILE}"

    if [[ "${mode}" == "run" ]]; then
        exec kitty --title "Hyprland bijwerken" bash -c '
            "$1"
            status=$?
            "$2" --refresh >/dev/null 2>&1 || true
            echo
            if (( status == 0 )); then
                echo ">> Bijwerken afgerond."
            else
                echo "!! Bijwerken is met fouten gestopt; zie de meldingen hierboven."
            fi
            read -r -p "Druk op Enter om dit venster te sluiten…" _
        ' _ "${repo}/update.sh" "${SELF}"
    fi

    exec kitty --title "Hyprland-updates controleren" bash -c '
        "$1" --check
        status=$?
        echo
        read -r -p "Druk op Enter om dit venster te sluiten…" _
        exit "${status}"
    ' _ "${repo}/update.sh"
}

case "${1:-}" in
    --refresh) refresh ;;
    --run) open_terminal run ;;
    --check) open_terminal check ;;
    -h|--help) usage ;;
    "")
        age=999999
        if [[ -s "${CACHE_FILE}" ]]; then
            age=$(( $(date +%s) - $(stat -c %Y "${CACHE_FILE}" 2>/dev/null || echo 0) ))
        fi
        if (( age >= CACHE_TTL )); then
            refresh
        else
            cat "${CACHE_FILE}"
        fi
        ;;
    *)
        echo "Onbekende optie: ${1}" >&2
        usage >&2
        exit 2
        ;;
esac
