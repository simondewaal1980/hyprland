#!/usr/bin/env bash
#
# fetch-greek-wallpapers.sh — haalt een set Griekse landschappen en
#                             stadsgezichten op van Wikimedia Commons.
#
# De afbeeldingen komen van Wikimedia Commons (vrije licenties). Er wordt een
# geschaalde versie (max. BREDE px) gedownload, niet het (vaak enorme) origineel.
#
# Gebruik:
#   ./fetch-greek-wallpapers.sh [doelmap]
#
# Zonder argument wordt ~/.local/share/wallpapers gebruikt — de map waarin
# qtile, pywal en de wallpaperkiezer (mod+shift+w) zoeken.
#
set -euo pipefail

DEST="${1:-${HOME}/.local/share/wallpapers}"
WIDTH=2560
UA='qtile-rice-wallpaper-fetch/1.0'
API='https://commons.wikimedia.org/w/api.php'

# Bestandsnaam (zonder .jpg) en bijbehorende zoekterm — één per afbeelding.
slugs=(
    santorini-oia    mykonos        acropolis      meteora       olympus
    crete            samaria-gorge  navagio        myrtos        rhodes
    corfu            monemvasia     nafplio        delphi        thessaloniki
    naxos            milos          parga          plaka         sounion
)
searches=(
    "Santorini Oia blue domes"          "Mykonos windmills Little Venice"
    "Acropolis of Athens Parthenon"     "Meteora monastery Greece"
    "Mount Olympus Greece landscape"    "Crete landscape mountains"
    "Samaria Gorge Crete"               "Navagio beach Zakynthos shipwreck"
    "Myrtos beach Kefalonia"            "Rhodes old town Greece"
    "Corfu town Greece"                 "Monemvasia Greece"
    "Nafplio Greece old town"           "Delphi Greece ruins"
    "Thessaloniki waterfront"           "Naxos Greece port"
    "Sarakiniko Milos"                  "Parga Greece"
    "Plaka Athens"                      "Temple of Poseidon Sounion"
)

mkdir -p "${DEST}"

# Kiest uit de zoekresultaten de grootste bruikbare JPEG (>= 1600 px breed)
# en print de URL van de geschaalde versie.
pick_url() {
    python3 -c '
import sys, json

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

pages = data.get("query", {}).get("pages", {})

def width(page):
    return page.get("imageinfo", [{}])[0].get("width", 0)

for page in sorted(pages.values(), key=width, reverse=True):
    info = page.get("imageinfo", [{}])[0]
    if info.get("mime") == "image/jpeg" and info.get("width", 0) >= 1600:
        print(info.get("thumburl") or info.get("url"))
        break
'
}

# Zoekt de URL; Wikimedia geeft af en toe een lege respons, dus een paar pogingen.
find_url() {
    local query="$1" url=""
    for _ in 1 2 3; do
        url="$(curl -sS -m 30 -A "${UA}" --get "${API}" \
            --data-urlencode 'action=query' \
            --data-urlencode 'generator=search' \
            --data-urlencode "gsrsearch=filetype:bitmap ${query}" \
            --data-urlencode 'gsrnamespace=6' \
            --data-urlencode 'gsrlimit=6' \
            --data-urlencode 'prop=imageinfo' \
            --data-urlencode 'iiprop=url|mime|size' \
            --data-urlencode "iiurlwidth=${WIDTH}" \
            --data-urlencode 'format=json' \
            | pick_url || true)"
        [[ -n "${url}" ]] && break
        sleep 2
    done
    printf '%s' "${url}"
}

ok=0
for i in "${!slugs[@]}"; do
    slug="${slugs[$i]}"
    query="${searches[$i]}"
    out="${DEST}/${slug}.jpg"

    printf '[%2d/%2d] %-16s %s' "$((i + 1))" "${#slugs[@]}" "${slug}" "${query}"
    [[ -e "${out}" ]] && printf '  (overschrijft bestaand bestand)'
    printf '\n'

    url="$(find_url "${query}")"

    if [[ -z "${url}" ]]; then
        echo "        !! geen geschikte afbeelding gevonden, overgeslagen" >&2
        continue
    fi

    if curl -sS -m 180 -A "${UA}" -L -o "${out}" "${url}"; then
        ok=$((ok + 1))
    else
        echo "        !! download mislukt: ${url}" >&2
        rm -f "${out}"
    fi
done

echo
echo ">> ${ok}/${#slugs[@]} wallpapers opgeslagen in ${DEST}"
