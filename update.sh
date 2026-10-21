#!/usr/bin/env bash
#
# update.sh — werk de Hyprland-desktopopzet bij.
#
# Naast de Ubuntu-pakketten zijn er vier bronnen buiten apt:
#   * Flatpak          apps en runtimes uit de geconfigureerde remotes
#   * pywal16          PyPI, geïnstalleerd met pipx
#   * JetBrainsMono    GitHub-releases van ryanoasis/nerd-fonts
#   * hyprlock         zelf gebouwd uit hyprwm/hyprlock
#
# Dit script controleert die bronnen, werkt bij wat verouderd is en zet daarna
# de configuraties uit deze map opnieuw in ~/.config.
#
# Gebruik:
#   ./update.sh                alles bijwerken
#   ./update.sh --check        alleen tonen wat verouderd is (wijzigt niets)
#   ./update.sh --no-apt       Ubuntu-pakketten overslaan
#   ./update.sh --no-config    configuraties niet opnieuw installeren
#   ./update.sh --help
#
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
    echo "!! Draai update.sh als je eigen gebruiker, niet met sudo." >&2
    echo "   Het script vraagt zelf om sudo waar dat nodig is." >&2
    exit 1
fi

# 'wal' staat na een pipx-installatie in ~/.local/bin.
export PATH="${HOME}/.local/bin:${PATH}"

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
FONT_DIR="${DATA_DIR}/fonts/JetBrainsMonoNerd"
APT_FILE="${REPO_DIR}/packages/apt.txt"

check_only=false
do_apt=true
do_flatpak=true
do_config=true

updates_available=0
failures=()
apt_upgraded=()

usage() {
    cat <<EOF
Gebruik: $(basename "$0") [opties]

Werkt de Hyprland-desktopopzet bij, inclusief software buiten de
Ubuntu-repositories:
  * Ubuntu-pakketten uit packages/apt.txt
  * Flatpak-apps en -runtimes
  * pywal16 (PyPI, via pipx)
  * JetBrainsMono Nerd Font (GitHub)
  * hyprlock (zelf gebouwd uit de GitHub-broncode)
  * de configuraties in ~/.config

Opties:
  --check        alleen tonen wat verouderd is; wijzigt niets
  --no-apt       Ubuntu-pakketten overslaan
  --no-flatpak   Flatpak-apps en -runtimes overslaan
  --no-config    configuraties niet opnieuw installeren
  -h, --help     deze uitleg tonen
EOF
}

say() { printf '>> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
info() { printf '   %s\n' "$*"; }

for opt in "$@"; do
    case "${opt}" in
        --check) check_only=true ;;
        --no-apt) do_apt=false ;;
        --no-flatpak) do_flatpak=false ;;
        --no-config) do_config=false ;;
        -h|--help) usage; exit 0 ;;
        *)
            warn "Onbekende optie: ${opt}"
            usage >&2
            exit 2
            ;;
    esac
done

# Is kandidaat nieuwer dan de geïnstalleerde versie? Lege 'huidig' geldt als
# onbekend en dus als verouderd.
version_gt() {
    local candidate="${1#v}" current="${2#v}"
    [[ -n "${candidate}" ]] || return 1
    [[ -n "${current}" ]] || return 0
    [[ "${candidate}" != "${current}" ]] || return 1
    [[ "$(printf '%s\n%s\n' "${candidate}" "${current}" | sort -V | tail -n 1)" == "${candidate}" ]]
}

github_latest_tag() {
    local repo="$1" effective tag
    effective="$(curl -fsSIL --max-time 20 -o /dev/null -w '%{url_effective}' \
        "https://github.com/${repo}/releases/latest" 2>/dev/null)" || return 1
    effective="${effective%/}"
    tag="${effective##*/}"
    [[ "${tag}" =~ ^v?[0-9] ]] || return 1
    printf '%s\n' "${tag}"
}

pypi_latest_version() {
    command -v jq >/dev/null 2>&1 || return 1
    curl -fsSL --max-time 20 "https://pypi.org/pypi/pywal16/json" 2>/dev/null \
        | jq -r '.info.version // empty' 2>/dev/null
}

pywal_installed_version() {
    pipx runpip pywal16 show pywal16 2>/dev/null \
        | awk -F': ' '/^Version:/ {print $2; exit}' || true
}

font_installed_version() {
    if [[ -s "${FONT_DIR}/.version" ]]; then
        head -n 1 "${FONT_DIR}/.version" | tr -d '[:space:]'
    elif [[ -f "${FONT_DIR}/README.md" ]]; then
        # Oudere installaties hebben nog geen .version; de README van de
        # Nerd Fonts-zip noemt de release wel.
        grep -oE 'v[0-9]+(\.[0-9]+)+' "${FONT_DIR}/README.md" 2>/dev/null | head -n 1 || true
    fi
}

update_apt() {
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get ontbreekt; Ubuntu-pakketten overgeslagen."
        return
    fi
    if [[ ! -f "${APT_FILE}" ]]; then
        warn "Pakkettenlijst ${APT_FILE} ontbreekt; Ubuntu-pakketten overgeslagen."
        return
    fi

    if ${check_only}; then
        local lists_time
        lists_time="$(stat -c '%y' /var/lib/apt/lists 2>/dev/null | cut -d. -f1 || true)"
        info "Pakketlijsten niet ververst (--check); laatst bijgewerkt: ${lists_time:-onbekend}."
    else
        say "Ubuntu-pakketten: pakketlijsten verversen…"
        if ! sudo apt-get update; then
            warn "apt-get update mislukt; ga verder met de bestaande pakketlijsten."
            failures+=("apt-get update")
        fi
    fi

    local -a packages=() upgradable=()
    mapfile -t packages < <(
        sed -e 's/#.*//' -e 's/[[:space:]]//g' "${APT_FILE}" \
            | sed '/^$/d' | sort -u
    )

    local pkg state installed candidate
    for pkg in "${packages[@]}"; do
        state="$(dpkg-query -W -f='${Status}|${Version}' "${pkg}" 2>/dev/null || true)"
        [[ "${state}" == "install ok installed|"* ]] || continue
        installed="${state#*|}"
        candidate="$(LC_ALL=C apt-cache policy "${pkg}" 2>/dev/null \
            | awk '/^  Candidate:/ {print $2; exit}' || true)"
        [[ -n "${candidate}" && "${candidate}" != "(none)" ]] || continue
        if [[ "${candidate}" != "${installed}" ]] && \
            dpkg --compare-versions "${candidate}" gt "${installed}"; then
            upgradable+=("${pkg}")
        fi
    done

    if [[ ${#upgradable[@]} -eq 0 ]]; then
        say "Ubuntu-pakketten: alles bij."
        return
    fi

    updates_available=$((updates_available + ${#upgradable[@]}))

    if ${check_only}; then
        say "Ubuntu-pakketten: ${#upgradable[@]} update(s): ${upgradable[*]}"
        return
    fi

    say "Ubuntu-pakketten bijwerken: ${upgradable[*]}"
    if sudo apt-get install -y --only-upgrade --no-install-recommends "${upgradable[@]}"; then
        apt_upgraded+=("${upgradable[@]}")
    else
        warn "Bijwerken van de Ubuntu-pakketten is mislukt."
        failures+=("apt")
    fi
}

flatpak_update_list() {
    # Toon wat er in beide installaties (systeem én gebruiker) verouderd is.
    local installation output
    local -a updates=()
    for installation in system user; do
        if [[ "${installation}" == "user" ]]; then
            output="$(flatpak remote-ls --user --updates --columns=application 2>/dev/null)" || return 1
        else
            output="$(flatpak remote-ls --system --updates --columns=application 2>/dev/null)" || return 1
        fi
        [[ -z "${output}" ]] || updates+=("${output}")
    done
    if [[ ${#updates[@]} -gt 0 ]]; then
        printf '%s\n' "${updates[@]}" | sort -u
    fi
}

update_flatpak() {
    if ! command -v flatpak >/dev/null 2>&1; then
        say "Flatpak: niet geïnstalleerd; overgeslagen."
        return
    fi

    local output
    if ! output="$(flatpak_update_list)"; then
        warn "Kon de Flatpak-updates niet ophalen; Flatpak overgeslagen."
        return
    fi

    local -a updates=()
    [[ -z "${output}" ]] || mapfile -t updates <<< "${output}"

    if [[ ${#updates[@]} -eq 0 ]]; then
        say "Flatpak: alles bij."
        return
    fi

    updates_available=$((updates_available + ${#updates[@]}))

    if ${check_only}; then
        say "Flatpak: ${#updates[@]} update(s): ${updates[*]}"
        return
    fi

    say "Flatpak bijwerken: ${updates[*]}"
    if ! flatpak update -y; then
        warn "Bijwerken van de Flatpak-apps en -runtimes is mislukt."
        failures+=("Flatpak")
    fi
}

update_pywal() {
    if ! command -v pipx >/dev/null 2>&1; then
        warn "pipx ontbreekt; pywal16 overgeslagen (installeer met ./install.sh --packages)."
        return
    fi

    local installed latest
    installed="$(pywal_installed_version || true)"
    latest="$(pypi_latest_version || true)"

    if [[ -z "${latest}" ]]; then
        warn "Kon de nieuwste pywal16-versie niet ophalen; pywal16 overgeslagen."
        return
    fi

    if [[ -n "${installed}" ]] && ! version_gt "${latest}" "${installed}"; then
        if version_gt "${installed}" "${latest}"; then
            say "pywal16: ${installed} (nieuwer dan PyPI: ${latest})"
        else
            say "pywal16: ${installed} (laatste)"
        fi
        return
    fi

    updates_available=$((updates_available + 1))

    if ${check_only}; then
        if [[ -n "${installed}" ]]; then
            say "pywal16: ${installed} -> ${latest}"
        else
            say "pywal16: niet geïnstalleerd (laatste: ${latest})"
        fi
        return
    fi

    if [[ -n "${installed}" ]]; then
        say "pywal16 bijwerken: ${installed} -> ${latest}…"
        if ! pipx upgrade pywal16; then
            warn "Bijwerken van pywal16 is mislukt."
            failures+=("pywal16")
        fi
    else
        say "pywal16 installeren (${latest})…"
        if ! pipx install pywal16; then
            warn "Installeren van pywal16 is mislukt."
            failures+=("pywal16")
        fi
    fi
}

update_font() {
    local installed latest
    installed="$(font_installed_version || true)"
    latest="$(github_latest_tag ryanoasis/nerd-fonts || true)"

    if [[ -z "${latest}" ]]; then
        warn "Kon de nieuwste Nerd Font-release niet ophalen; font overgeslagen."
        return
    fi

    if [[ -n "${installed}" ]] && ! version_gt "${latest}" "${installed}"; then
        if version_gt "${installed}" "${latest}"; then
            say "Nerd Font: ${installed} (nieuwer dan GitHub: ${latest})"
        else
            say "Nerd Font: ${installed} (laatste)"
        fi
        return
    fi

    updates_available=$((updates_available + 1))

    if ${check_only}; then
        say "Nerd Font: ${installed:-onbekend} -> ${latest}"
        return
    fi

    say "Nerd Font bijwerken: ${installed:-onbekend} -> ${latest}…"
    local tmp
    tmp="$(mktemp -d)"
    if ! curl -fsSL --max-time 180 -o "${tmp}/JetBrainsMono.zip" \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/${latest}/JetBrainsMono.zip"; then
        warn "Downloaden van de Nerd Font is mislukt; de huidige versie blijft staan."
        failures+=("Nerd Font")
        rm -rf "${tmp}"
        return
    fi

    mkdir -p "${tmp}/new"
    if ! unzip -oq "${tmp}/JetBrainsMono.zip" -d "${tmp}/new"; then
        warn "Uitpakken van de Nerd Font is mislukt; de huidige versie blijft staan."
        failures+=("Nerd Font")
        rm -rf "${tmp}"
        return
    fi
    if ! find "${tmp}/new" -maxdepth 1 -name '*.ttf' -print -quit | grep -q .; then
        warn "De gedownloade Nerd Font bevat geen lettertypebestanden; niets vervangen."
        failures+=("Nerd Font")
        rm -rf "${tmp}"
        return
    fi

    printf '%s\n' "${latest}" > "${tmp}/new/.version"
    mkdir -p "$(dirname "${FONT_DIR}")"
    rm -rf "${FONT_DIR}.old"
    if [[ -d "${FONT_DIR}" ]]; then
        mv "${FONT_DIR}" "${FONT_DIR}.old"
    fi
    if ! mv "${tmp}/new" "${FONT_DIR}"; then
        warn "Nieuwe Nerd Font plaatsen mislukt; oude versie teruggezet."
        if [[ -d "${FONT_DIR}.old" ]]; then
            mv "${FONT_DIR}.old" "${FONT_DIR}"
        fi
        failures+=("Nerd Font")
        rm -rf "${tmp}"
        return
    fi
    rm -rf "${FONT_DIR}.old" "${tmp}"
    fc-cache -f >/dev/null 2>&1 || true
    say "Nerd Font ${latest} geïnstalleerd."
}

update_hyprlock() {
    if ! command -v hyprlock >/dev/null 2>&1; then
        warn "hyprlock ontbreekt; overgeslagen (installeer met ./install.sh --packages)."
        return
    fi

    local installed latest
    installed="$(hyprlock --version 2>/dev/null | head -n 1 \
        | grep -oE 'v?[0-9]+(\.[0-9]+)+' | head -n 1 || true)"
    latest="$(github_latest_tag hyprwm/hyprlock || true)"

    if [[ -z "${latest}" ]]; then
        warn "Kon de nieuwste hyprlock-release niet ophalen; hyprlock overgeslagen."
        return
    fi

    if [[ -n "${installed}" ]] && ! version_gt "${latest}" "${installed}"; then
        if version_gt "${installed}" "${latest}"; then
            say "hyprlock: ${installed} (nieuwer dan GitHub: ${latest})"
        else
            say "hyprlock: ${installed} (laatste)"
        fi
        return
    fi

    updates_available=$((updates_available + 1))

    if ${check_only}; then
        say "hyprlock: ${installed:-onbekend} -> ${latest} (opnieuw bouwen)"
        return
    fi

    say "hyprlock bouwen: ${installed:-onbekend} -> ${latest}…"
    if ! "${REPO_DIR}/packages/build-hyprlock.sh" "${latest}"; then
        warn "Bouwen van hyprlock ${latest} is mislukt; de huidige versie blijft staan."
        failures+=("hyprlock")
    fi
}

update_configs() {
    if ! ${do_config}; then
        return
    fi

    if ${check_only}; then
        say "Configuraties: bijwerken kopieert ${REPO_DIR} opnieuw naar ~/.config."
        return
    fi

    say "Configuraties uit ${REPO_DIR} installeren…"
    if ! "${REPO_DIR}/install.sh"; then
        warn "install.sh is mislukt."
        failures+=("configuraties")
    fi
}

if ${check_only}; then
    echo ">> Hyprland-desktopopzet controleren…"
else
    echo ">> Hyprland-desktopopzet bijwerken…"
fi

if ${do_apt}; then
    update_apt
fi
if ${do_flatpak}; then
    update_flatpak
fi
update_pywal
update_font
update_hyprlock
update_configs

echo
if ${check_only}; then
    if [[ ${updates_available} -eq 0 ]]; then
        say "Alles is bij."
    else
        say "${updates_available} update(s) beschikbaar. Draai ./update.sh om ze te installeren."
    fi
    exit 0
fi

if [[ ${#failures[@]} -gt 0 ]]; then
    warn "Bijwerken klaar met ${#failures[@]} fout(en): ${failures[*]}"
    exit 1
fi

say "Klaar: alles is bijgewerkt."
if [[ " ${apt_upgraded[*]} " == *" hyprland "* ]]; then
    info "Hyprland zelf is bijgewerkt; log uit en weer in om de nieuwe versie te gebruiken."
fi
