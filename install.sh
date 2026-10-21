#!/usr/bin/env bash
#
# install.sh — zet de Hyprland-desktopopzet uit deze map op zijn plek.
#
# Gebruik:
#   ./install.sh              configuraties installeren
#   ./install.sh --packages   ook de benodigde software installeren (Ubuntu)
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
STAMP="$(date +%Y%m%d-%H%M%S)"

install_packages=false
[[ "${1:-}" == "--packages" ]] && install_packages=true

if ${install_packages}; then
    if ! command -v apt-get >/dev/null 2>&1; then
        echo "!! Deze installatie is geschreven voor Ubuntu/Debian (apt)." >&2
        echo "   Installeer de pakketten uit packages/apt.txt handmatig." >&2
        exit 1
    fi

    echo ">> Pakketten installeren…"
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends \
        hyprland hyprpaper hyprlock hypridle hyprpicker hyprpolkitagent \
        hyprland-qtutils waybar wofi mako-notifier rofi kitty \
        grim slurp wl-clipboard cliphist swappy \
        xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
        dolphin dolphin-plugins kate okular gwenview haruna elisa ark \
        kio-extras kio-admin kde-cli-tools plasma-integration \
        libkf6service-bin desktop-file-utils \
        libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-draw \
        qt6ct qt5ct nwg-look papirus-icon-theme bibata-cursor-theme \
        blueman brightnessctl playerctl network-manager-gnome wlogout \
        fonts-inter fonts-jetbrains-mono fonts-noto-color-emoji \
        imagemagick jq curl libnotify-bin xdg-utils unzip pipx python3

    if ! command -v wal >/dev/null 2>&1; then
        echo ">> pywal16 via pipx installeren…"
        pipx install pywal16 || pipx upgrade pywal16 || true
        export PATH="${HOME}/.local/bin:${PATH}"
    fi
fi

# Nerd Font voor de pictogrammen in Waybar en wlogout.
if ! fc-list : family 2>/dev/null | grep -i 'JetBrainsMono Nerd' >/dev/null; then
    echo ">> JetBrainsMono Nerd Font downloaden…"
    mkdir -p "${DATA_DIR}/fonts/JetBrainsMonoNerd"
    tmp="$(mktemp -d)"
    if curl -fsSL -o "${tmp}/JetBrainsMono.zip" \
        https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip; then
        unzip -oq "${tmp}/JetBrainsMono.zip" -d "${DATA_DIR}/fonts/JetBrainsMonoNerd"
        # Versie bewaren, zodat update.sh weet of er een nieuwere release is.
        font_version="$(grep -oE 'v[0-9]+(\.[0-9]+)+' \
            "${DATA_DIR}/fonts/JetBrainsMonoNerd/README.md" 2>/dev/null | head -n 1 || true)"
        if [[ -n "${font_version}" ]]; then
            printf '%s\n' "${font_version}" \
                > "${DATA_DIR}/fonts/JetBrainsMonoNerd/.version"
        fi
        fc-cache -f >/dev/null 2>&1 || true
    else
        echo "!! Nerd Font downloaden mislukt; pictogrammen kunnen ontbreken." >&2
    fi
    rm -rf "${tmp}"
fi

# Nederlandse datums in Waybar en op het vergrendelscherm.
if ! locale -a 2>/dev/null | grep -qi '^nl_NL'; then
    echo "!! De locale nl_NL.UTF-8 ontbreekt; de klok in Waybar blijft dan leeg." >&2
    echo "   Zet hem aan met: sudo locale-gen nl_NL.UTF-8" >&2
fi

# Ubuntu 26.04 levert hyprlock 0.9.2, die kort na het vergrendelen crasht.
if command -v hyprlock >/dev/null 2>&1; then
    hl_ver="$(hyprlock --version 2>/dev/null | head -1 | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
    if [[ -n "${hl_ver}" ]] && \
       [[ "$(printf '%s\n%s\n' "${hl_ver}" 0.9.3 | sort -V | head -1)" == "${hl_ver}" ]] && \
       [[ "${hl_ver}" != "0.9.3" ]]; then
        echo "!! hyprlock ${hl_ver} crasht op Ubuntu 26.04 zodra het scherm vergrendelt." >&2
        echo "   Bouw een recente versie met: packages/build-hyprlock.sh" >&2
    fi
fi

# Back-up maken van bestaande configuratie, tenzij die van deze rice is.
backup_if_needed() {
    local target="$1"
    if [[ -e "${target}" && ! -e "${target}/.hyprland-rice" ]]; then
        echo ">> Bestaande configuratie back-uppen: ${target} -> ${target}.bak-${STAMP}"
        mv "${target}" "${target}.bak-${STAMP}"
    fi
}

install_tree() {
    local src="$1" dest="$2"
    backup_if_needed "${dest}"
    mkdir -p "${dest}"
    cp -a "${src}/." "${dest}/"
    touch "${dest}/.hyprland-rice"
}

echo ">> Configuraties installeren in ${CONFIG_DIR}…"
install_tree "${REPO_DIR}/hypr" "${CONFIG_DIR}/hypr"
install_tree "${REPO_DIR}/waybar" "${CONFIG_DIR}/waybar"
install_tree "${REPO_DIR}/wofi" "${CONFIG_DIR}/wofi"
install_tree "${REPO_DIR}/mako" "${CONFIG_DIR}/mako"
install_tree "${REPO_DIR}/wlogout" "${CONFIG_DIR}/wlogout"

# De CSS-bestanden importeren de kleuren via een absoluut pad; dat werkt ook
# als een app vanuit een andere werkmap wordt gestart.
for css in waybar/style.css wofi/style.css wlogout/style.css; do
    sed -i "s|__CONFIG_DIR__|${CONFIG_DIR}|g" "${CONFIG_DIR}/${css}"
done

chmod 755 "${CONFIG_DIR}/hypr/scripts/"*.sh
chmod 755 "${CONFIG_DIR}/hypr/scripts/theme-gen.py"

# Onthoud waar deze rice staat, zodat de update-knop in Waybar update.sh vindt.
printf '%s\n' "${REPO_DIR}" > "${CONFIG_DIR}/hypr/.repo-path"

# Bestandskoppelingen: tekst → Kate, pdf → Okular, beeld → Gwenview, enz.
# Het script vult ~/.config/mimeapps.list aan en herbouwt de KDE-servicecache
# met XDG_MENU_PREFIX=plasma-, zodat Dolphin de standaardapps vindt.
echo ">> Bestandskoppelingen instellen…"
if ! "${CONFIG_DIR}/hypr/scripts/apply-default-apps.sh"; then
    echo "!! Bestandskoppelingen instellen is mislukt." >&2
fi

# Kitty: thema-include toevoegen zonder de bestaande config te vervangen.
KITTY_DIR="${CONFIG_DIR}/kitty"
mkdir -p "${KITTY_DIR}"
if [[ -f "${KITTY_DIR}/kitty.conf" ]]; then
    if ! grep -qF 'hyprland-theme.conf' "${KITTY_DIR}/kitty.conf"; then
        [[ -e "${KITTY_DIR}/kitty.conf.bak-${STAMP}" ]] || \
            cp "${KITTY_DIR}/kitty.conf" "${KITTY_DIR}/kitty.conf.bak-${STAMP}"
        printf '\n# Hyprland-desktopopzet: dynamische kleuren en vensteropmaak.\ninclude ~/.config/kitty/hyprland-theme.conf\n' \
            >> "${KITTY_DIR}/kitty.conf"
    fi
else
    printf '# Kitty — Hyprland-desktopopzet\ninclude ~/.config/kitty/hyprland-theme.conf\n' \
        > "${KITTY_DIR}/kitty.conf"
fi

# OpenCode: laat de TUI het gegenereerde 'wal'-thema gebruiken. Alleen het
# theme-blok in cli.json wordt aangepast; andere instellingen blijven staan.
OPENCODE_DIR="${CONFIG_DIR}/opencode"
if [[ -d "${OPENCODE_DIR}" ]] || command -v opencode >/dev/null 2>&1; then
    mkdir -p "${OPENCODE_DIR}/themes"
    opencode_cli="${OPENCODE_DIR}/cli.json"
    if [[ ! -e "${opencode_cli}" ]]; then
        cat > "${opencode_cli}" <<'JSON'
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "theme": {
    "name": "wal",
    "mode": "dark"
  }
}
JSON
    elif ! python3 - "${opencode_cli}" <<'PY'
import json
import os
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"kan {path} niet lezen: {exc}")

theme = data.get("theme")
if not isinstance(theme, dict):
    theme = {}
if theme.get("name") != "wal":
    theme["name"] = "wal"
    theme.setdefault("mode", "dark")
    data["theme"] = theme
    tmp = f"{path}.tmp-{os.getpid()}"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
PY
    then
        echo "!! OpenCode-thema instellen is mislukt; cli.json is ongewijzigd." >&2
    fi
fi

# systemd-user-timer voor de automatische wallpaperwissel.
mkdir -p "${CONFIG_DIR}/systemd/user"
install -m 644 "${REPO_DIR}/systemd/hyprland-wallpaper-rotate.service" \
    "${CONFIG_DIR}/systemd/user/"
install -m 644 "${REPO_DIR}/systemd/hyprland-wallpaper-rotate.timer" \
    "${CONFIG_DIR}/systemd/user/"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now hyprland-wallpaper-rotate.timer 2>/dev/null || true

# Wallpapers: gebruik de bestaande set, of haal de voorbeeldset op.
mkdir -p "${DATA_DIR}/wallpapers"
if ! find "${DATA_DIR}/wallpapers" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -print -quit 2>/dev/null | grep -q .; then
    echo ">> Geen wallpapers gevonden; Griekse voorbeeldset ophalen…"
    "${REPO_DIR}/wallpapers/fetch-greek-wallpapers.sh" "${DATA_DIR}/wallpapers" || true
fi

if command -v wal >/dev/null 2>&1; then
    echo ">> Eerste kleurenschema genereren…"
    "${CONFIG_DIR}/hypr/scripts/set-wallpaper.sh" || true
else
    echo "!! 'wal' (pywal16) niet gevonden. Installeer met: ./install.sh --packages" >&2
    echo "   Of: pipx install pywal16" >&2
fi

echo
echo ">> Klaar."
echo "   Log uit en kies bij het inloggen de sessie 'Hyprland'."
echo "   Sneltoetsen: Super+D (apps), Super+Return (terminal), Super+W (wallpaper)."
echo "   De wallpaper wisselt automatisch elke 10 minuten."
