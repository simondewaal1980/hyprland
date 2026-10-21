#!/usr/bin/env bash
#
# connect-soundcore.sh — verbind de soundcore Space One Pro bij het inloggen.
#
# BlueZ heeft na het starten van de sessie soms een paar seconden nodig voordat
# de adapter klaar is. Daarom wacht dit script tot de adapter is ingeschakeld en
# proberen we het daarna een aantal keer. Staat de koptelefoon uit, dan stopt het
# script zonder melding; BlueZ verbindt hem later alsnog omdat hij 'trusted' is.
#
set -u

MAC="7C:E9:13:93:7A:2A"
POGINGEN=12
INTERVAL=5

command -v bluetoothctl >/dev/null 2>&1 || exit 0

adapter_klaar() {
    bluetoothctl show 2>/dev/null | grep -q '^[[:space:]]*Powered: yes'
}

al_verbonden() {
    bluetoothctl info "${MAC}" 2>/dev/null | grep -q 'Connected: yes'
}

# Wacht maximaal een minuut tot de Bluetooth-adapter bestaat en aan staat.
for ((i = 0; i < POGINGEN; i++)); do
    adapter_klaar && break
    sleep "${INTERVAL}"
done
adapter_klaar || exit 0

# Niets doen als de koptelefoon al verbonden is.
al_verbonden && exit 0

# Een headset die uit staat laat 'connect' lang wachten; timeout voorkomt dat
# het script blijft hangen en de volgende poging nooit aan de beurt komt.
for ((poging = 1; poging <= POGINGEN; poging++)); do
    if timeout 10 bluetoothctl connect "${MAC}" >/dev/null 2>&1; then
        exit 0
    fi
    al_verbonden && exit 0
    sleep "${INTERVAL}"
done

exit 0
