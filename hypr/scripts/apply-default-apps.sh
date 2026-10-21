#!/usr/bin/env bash
#
# apply-default-apps.sh — koppel bestandstypen aan de juiste applicaties.
#
# Leest de standaardapps uit ~/.config/hypr/mimeapps.list en zet elke regel uit
# [Default Applications] met xdg-mime. Koppelingen voor andere typen en eigen
# URL-schema's in ~/.config/mimeapps.list blijven gewoon staan.
#
# Daarna wordt de KDE-servicecache opnieuw opgebouwd. Dat gebeurt met
# XDG_MENU_PREFIX=plasma-: zonder die prefix vindt Dolphin het Plasma-menu
# niet, kent hij geen standaardapps en toont hij een leeg "Openen met"-venster
# in plaats van het gekozen programma.
#
# Gebruik:
#   apply-default-apps.sh [bestand]
#
# Wordt automatisch aangeroepen door install.sh.
#
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
DEFAULTS="${1:-${CONFIG_DIR}/hypr/mimeapps.list}"
TARGET="${CONFIG_DIR}/mimeapps.list"

if [[ ! -f "${DEFAULTS}" ]]; then
    echo "!! ${DEFAULTS} ontbreekt; bestandskoppelingen niet ingesteld." >&2
    exit 1
fi

if ! command -v xdg-mime >/dev/null 2>&1; then
    echo "!! xdg-mime ontbreekt; installeer xdg-utils." >&2
    exit 1
fi

mkdir -p "${CONFIG_DIR}"

# Zoekt een desktop-bestand in dezelfde mappen die ook door xdg-mime en
# Dolphin worden gebruikt. Onbekende apps slaan we over: een koppeling naar
# een niet-geïnstalleerd programma levert juist een leeg "Openen met"-venster.
declare -A desktop_exists_cache=()
desktop_exists() {
    local id="$1" dir
    if [[ -n "${desktop_exists_cache[${id}]:-}" ]]; then
        return 0
    fi

    local -a app_dirs=("${DATA_DIR}/applications")
    local -a data_dirs=()
    IFS=':' read -r -a data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${data_dirs[@]}"; do
        [[ -n "${dir}" ]] && app_dirs+=("${dir}/applications")
    done
    for dir in /var/lib/flatpak/exports/share/applications \
        /var/lib/snapd/desktop/applications; do
        [[ -d "${dir}" ]] && app_dirs+=("${dir}")
    done

    for dir in "${app_dirs[@]}"; do
        if [[ -f "${dir}/${id}" ]]; then
            desktop_exists_cache[${id}]=1
            return 0
        fi
    done
    return 1
}

target_existed=false
[[ -f "${TARGET}" ]] && target_existed=true
backup="${TARGET}.bak-$(date +%Y%m%d-%H%M%S)"
${target_existed} && cp -a "${TARGET}" "${backup}"

in_defaults=false
applied=0
skipped=0
while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue

    if [[ "${line}" =~ ^\[(.+)\]$ ]]; then
        [[ "${BASH_REMATCH[1]}" == "Default Applications" ]] && in_defaults=true || in_defaults=false
        continue
    fi
    ${in_defaults} || continue
    [[ "${line}" == *=* ]] || continue

    mime="${line%%=*}"
    desktop="${line#*=}"
    mime="${mime//[[:space:]]/}"
    desktop="${desktop//[[:space:]]/}"
    [[ -n "${mime}" && -n "${desktop}" ]] || continue

    if ! desktop_exists "${desktop}"; then
        printf '!! %-34s -> %s (niet geïnstalleerd, overgeslagen)\n' \
            "${mime}" "${desktop}" >&2
        skipped=$((skipped + 1))
        continue
    fi

    if ! xdg-mime default "${desktop}" "${mime}" 2>/dev/null; then
        printf '!! %-34s -> %s (niet ingesteld)\n' "${mime}" "${desktop}" >&2
        skipped=$((skipped + 1))
        continue
    fi
    applied=$((applied + 1))
done < "${DEFAULTS}"

# De MIME-cache van de eigen desktop-bestanden en de KDE-servicecache
# verversen, zodat Dolphin de nieuwe koppelingen meteen ziet.
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${DATA_DIR}/applications" >/dev/null 2>&1 || true
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    XDG_MENU_PREFIX="${XDG_MENU_PREFIX:-plasma-}" \
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

if ${target_existed} && cmp -s "${backup}" "${TARGET}"; then
    rm -f "${backup}"
elif ${target_existed}; then
    echo ">> Oude koppelingen bewaard als ${backup}"
fi

echo ">> Bestandskoppelingen: ${applied} typen ingesteld, ${skipped} overgeslagen."
