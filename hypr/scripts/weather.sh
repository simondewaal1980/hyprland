#!/usr/bin/env bash
# Weer voor Eindhoven in de Waybar.
#
# Bron: Open-Meteo (gratis, geen API-sleutel). Het resultaat wordt tien minuten
# gecachet en als JSON aan Waybar gegeven ("return-type": "json"): tekst,
# tooltip en een CSS-class per weertype.
#
#   weather.sh             # gecachet resultaat (verversen indien nodig)
#   weather.sh --refresh   # nu verversen

set -u

CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/hyprland-weather"
CACHE_FILE="${CACHE_DIR}/eindhoven.json"
CACHE_TTL=600
API="https://api.open-meteo.com/v1/forecast?latitude=51.4416&longitude=5.4697&current=temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m&timezone=Europe%2FAmsterdam"

mkdir -p "${CACHE_DIR}" 2>/dev/null || true

refresh() {
    local tmp
    tmp="$(mktemp "${CACHE_DIR}/.eindhoven.XXXXXX")" || return 1
    if curl -fsS --max-time 8 "${API}" -o "${tmp}" &&
       jq -e '.current.temperature_2m != null and .current.weather_code != null' \
           "${tmp}" >/dev/null 2>&1; then
        mv "${tmp}" "${CACHE_FILE}"
    else
        rm -f "${tmp}"
        return 1
    fi
}

age=0
if [[ -s "${CACHE_FILE}" ]]; then
    age=$(( $(date +%s) - $(stat -c %Y "${CACHE_FILE}" 2>/dev/null || echo 0) ))
fi

if [[ "${1:-}" == "--refresh" ]] || [[ ! -s "${CACHE_FILE}" ]] ||
   (( age >= CACHE_TTL )); then
    refresh || true
fi

if ! jq -e '.current' "${CACHE_FILE}" >/dev/null 2>&1; then
    jq -cn --arg text $'\U000f0590  --°' \
        '{text: $text, tooltip: "Weer voor Eindhoven is nu niet beschikbaar", class: "unavailable"}'
    exit 0
fi

read -r temp feels humidity wind code day updated < <(
    jq -r '.current | "\(.temperature_2m) \(.apparent_temperature) \(.relative_humidity_2m) \(.wind_speed_10m) \(.weather_code) \(.is_day) \(.time)"' \
        "${CACHE_FILE}"
)

# WMO-weercodes → pictogram (Material Design Icons uit de Nerd Font),
# Nederlandse omschrijving en CSS-class.
case "${code}" in
    0)  if [[ "${day}" == "1" ]]; then icon=$'\U000f0599'; else icon=$'\U000f0594'; fi
        desc="Onbewolkt"; class="clear" ;;
    1)  icon=$'\U000f0595'; desc="Overwegend helder"; class="clear" ;;
    2)  icon=$'\U000f0595'; desc="Gedeeltelijk bewolkt"; class="cloudy" ;;
    3)  icon=$'\U000f0590'; desc="Bewolkt"; class="cloudy" ;;
    45|48) icon=$'\U000f0591'; desc="Mist"; class="fog" ;;
    51|53|55) icon=$'\U000f0596'; desc="Motregen"; class="rain" ;;
    56|57) icon=$'\U000f0592'; desc="IJzel"; class="rain" ;;
    61) icon=$'\U000f0596'; desc="Lichte regen"; class="rain" ;;
    63) icon=$'\U000f0596'; desc="Regen"; class="rain" ;;
    65) icon=$'\U000f0596'; desc="Zware regen"; class="rain" ;;
    66|67) icon=$'\U000f0592'; desc="IJzel"; class="rain" ;;
    71) icon=$'\U000f0597'; desc="Lichte sneeuw"; class="snow" ;;
    73) icon=$'\U000f0597'; desc="Sneeuw"; class="snow" ;;
    75) icon=$'\U000f0597'; desc="Zware sneeuw"; class="snow" ;;
    77) icon=$'\U000f0597'; desc="Sneeuwkorrels"; class="snow" ;;
    80) icon=$'\U000f0596'; desc="Lichte buien"; class="rain" ;;
    81) icon=$'\U000f0596'; desc="Buien"; class="rain" ;;
    82) icon=$'\U000f0596'; desc="Zware buien"; class="rain" ;;
    85|86) icon=$'\U000f0597'; desc="Sneeuwbuien"; class="snow" ;;
    95) icon=$'\U000f0593'; desc="Onweer"; class="storm" ;;
    96|99) icon=$'\U000f0593'; desc="Onweer met hagel"; class="storm" ;;
    *)  icon=$'\U000f0590'; desc="Onbekend"; class="cloudy" ;;
esac

temp="$(LC_ALL=C printf '%.0f' "${temp}")"
feels="$(LC_ALL=C printf '%.0f' "${feels}")"
wind="$(LC_ALL=C printf '%.0f' "${wind}")"
time="${updated#*T}"

tooltip="Eindhoven — ${desc}"$'\n'
tooltip+="${temp}°C (voelt als ${feels}°C)"$'\n'
tooltip+="Vochtigheid: ${humidity}%"$'\n'
tooltip+="Wind: ${wind} km/u"$'\n'
tooltip+="Bijgewerkt: ${time}"

jq -cn \
    --arg text "${icon}  ${temp}°" \
    --arg tooltip "${tooltip}" \
    --arg class "${class}" \
    '{text: $text, tooltip: $tooltip, class: $class}'
