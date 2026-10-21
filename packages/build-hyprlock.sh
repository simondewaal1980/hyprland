#!/usr/bin/env bash
#
# build-hyprlock.sh — bouw een recente hyprlock uit de broncode.
#
# Ubuntu 26.04 levert hyprlock 0.9.2. Die versie crasht kort nadat het scherm
# vergrendeld is (use-after-free in de async resource-gatherer, opgelost in
# hyprwm/hyprlock#961, uitgebracht in 0.9.3). Dit script bouwt 0.9.6 en zet
# hem in /usr/local/bin, dat vóór /usr/bin in het PATH staat. De originele
# pakketversie blijft dus gewoon staan.
#
# Gebruik:
#   ./build-hyprlock.sh            # versie v0.9.6 (standaard)
#   ./build-hyprlock.sh v0.9.5     # of een andere tag/branch
#
set -euo pipefail

VERSION="${1:-v0.9.6}"
BUILD_DIR="${BUILD_DIR:-/tmp/hyprlock-build}"

if ! command -v sudo >/dev/null 2>&1; then
    echo "!! sudo ontbreekt; installeer en bouw handmatig." >&2
    exit 1
fi

DEPS=(
    git cmake ninja-build pkg-config
    libhyprutils-dev libhyprlang-dev libhyprgraphics-dev libsdbus-c++-dev
    libpam0g-dev libpango1.0-dev libcairo2-dev libdrm-dev libgbm-dev
    libegl-dev libgles-dev libxkbcommon-dev libwayland-dev wayland-protocols
    hyprwayland-scanner libmagic-dev libjpeg-dev libwebp-dev
)

missing=()
for pkg in "${DEPS[@]}"; do
    dpkg -s "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo ">> Bouwpakketten installeren: ${missing[*]}"
    sudo apt-get install -y --no-install-recommends "${missing[@]}"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [[ ! -d hyprlock/.git ]]; then
    echo ">> Broncode ophalen (${VERSION})…"
    git clone --depth 1 --branch "${VERSION}" --recursive \
        https://github.com/hyprwm/hyprlock hyprlock
else
    echo ">> Bestaande broncode bijwerken naar ${VERSION}…"
    git -C hyprlock fetch --depth 1 --force origin "${VERSION}"
    git -C hyprlock checkout -f FETCH_HEAD
    git -C hyprlock submodule update --init --recursive --depth 1
fi

cd hyprlock
echo ">> Bouwen…"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local >/dev/null
cmake --build build

echo ">> Installeren in /usr/local/bin…"
sudo cmake --install build >/dev/null

hash -r 2>/dev/null || true
echo ">> Klaar: $(command -v hyprlock) — $(hyprlock --version | head -1)"
echo "   Vergrendel opnieuw met Super+L om te testen."
