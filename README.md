# Hyprland-desktopopzet

Een complete Hyprland-omgeving voor Ubuntu 26.04, gebouwd bovenop de bestaande
pywal16-opzet: **wallpaper wisselt automatisch**, **alle apps nemen de kleuren van
de wallpaper over** en de bar is een moderne Waybar met blur en afgeronde hoeken.

Deze map is de bron van waaruit `install.sh` alles naar `~/.config` kopieert.
De qtile-opzet die al op deze machine staat blijft gewoon werken.

## Wat je krijgt

* **Hyprland 0.53** — afgeronde hoeken (14 px), gaten, blur, schaduwen en vloeiende animaties.
* **Waybar** — workspaces met pictogrammen, venstertitel, klok met Nederlandse
  kalender (muisklik), weer voor Eindhoven (Open-Meteo), muziekspeler,
  systeemvak, netwerk, bluetooth, volume, CPU, geheugen, accu, wallpaper-knop
  en power-knop.
* **Automatische wallpaperwissel** — elke 10 minuten, via een systemd-user-timer
  die alleen draait als Hyprland de actieve sessie is.
* **Kleuren die meebewegen** — pywal16 haalt het palet uit de wallpaper; dat palet
  komt terecht in Hyprland, Waybar, wofi, rofi, wlogout, mako, kitty, hyprlock,
  **GTK-apps** (via een gegenereerd GTK-thema) en **Qt/KDE-apps** (Breeze + het
  KDE-kleurenschema *Pywal*).
* **Vergrendelen en sluimeren** — hyprlock (met klok, datum en wachtwoordveld) en
  hypridle: na 5 minuten vergrendelen, na 10 minuten het scherm uit.
  Let op: Ubuntu 26.04 levert hyprlock 0.9.2, die kort na het vergrendelen
  crasht; daarom staat hier een zelfgebouwde 0.9.6 in `/usr/local/bin`
  (zie [Vergrendelscherm](#vergrendelscherm-hyprlock)).
* **Hulpmiddelen** — wlogout power-menu, klembordgeschiedenis (cliphist),
  schermafdrukken (grim/slurp/swappy), kleurenpicker (hyprpicker),
  blueman en nm-applet in het systeemvak.

## Installeren

```bash
cd ~/Projecten/Hyprland
./install.sh --packages     # software installeren + configuraties plaatsen
./install.sh                # alleen de configuraties (bij)werken
./update.sh                 # alles bijwerken (zie hieronder)
```

`install.sh` doet het volgende:

1. Installeert de pakketten uit `packages/apt.txt` (alleen met `--packages`) en
   pywal16 via `pipx` als `wal` nog ontbreekt.
2. Zet de JetBrainsMono Nerd Font in `~/.local/share/fonts` (voor de pictogrammen).
3. Maakt een back-up van bestaande configuraties (`~/.config/hypr` enzovoort naar
   `~/.config/hypr.bak-<datum>`) en kopieert daarna `hypr/`, `waybar/`, `wofi/`,
   `mako/` en `wlogout/` naar `~/.config`. Elke gekopieerde map krijgt een
   `.hyprland-rice`-marker, zodat een tweede keer installeren geen nieuwe back-up maakt.
4. Voegt aan `~/.config/kitty/kitty.conf` één regel toe:
   `include ~/.config/kitty/hyprland-theme.conf` (kitty houdt dus je eigen instellingen).
5. Installeert en start de wallpaper-timer en genereert meteen het eerste kleurenschema.
6. Controleert of de locale `nl_NL.UTF-8` en een werkende hyprlock-versie aanwezig
   zijn en waarschuwt zo nodig (zie [Vergrendelscherm](#vergrendelscherm-hyprlock)).

> Draai je `./install.sh --packages` en vraagt `sudo` om een wachtwoord? Dat is
> alleen voor `apt-get`; de rest gebeurt in je eigen thuismap.

### Bijwerken

```bash
./update.sh            # alles bijwerken
./update.sh --check    # alleen tonen wat verouderd is
```

`update.sh` werkt niet alleen de Ubuntu-pakketten uit `packages/apt.txt` bij,
maar ook de onderdelen die niet uit de Kubuntu-repositories komen:

| Bron | Wat het script doet |
| --- | --- |
| pywal16 (PyPI) | `pipx upgrade pywal16`, of installeren als het ontbreekt |
| JetBrainsMono Nerd Font (GitHub) | de nieuwste release downloaden als die nieuwer is |
| hyprlock (GitHub-broncode) | een nieuwe release bouwen naar `/usr/local/bin` |
| deze configuratiemap | opnieuw via `install.sh` naar `~/.config` kopiëren |

Alleen de pakketten die in `packages/apt.txt` staan en al geïnstalleerd zijn,
worden bijgewerkt; je hele systeem wordt niet geüpgraded. Met `--no-apt` sla je
de Ubuntu-pakketten over en met `--no-config` de configuraties. `--check`
wijzigt niets en gebruikt de bestaande apt-pakketlijsten; heb je net
`sudo apt-get update` gedraaid, dan is de controle het meest actueel.

### Inloggen

Log uit en kies bij het inloggen (SDDM) de sessie **Hyprland** in plaats van
Plasma. Handmatig starten kan ook met `start-hyprland`.

## Sneltoetsen

De belangrijkste (de volledige lijst staat in [docs/sneltoetsen.md](docs/sneltoetsen.md)):

| Toets | Actie |
| --- | --- |
| `Super` + `Return` | Terminal (kitty) |
| `Super` + `D` | Applicatiemenu (wofi) |
| `Super` + `W` | Wallpaper kiezen (galerij met thumbnails) |
| `Super` + `Shift` + `W` | Volgende wallpaper |
| `Super` + `Q` | Venster sluiten |
| `Super` + `1`…`0` | Naar workspace 1–10 |
| `Super` + `L` | Scherm vergrendelen |
| `Super` + `Escape` | Power-menu (wlogout) |
| `Super` + `R` / `U` | Hyprland / Waybar opnieuw laden |

## Hoe het thema werkt

```
wallpapers in ~/.local/share/wallpapers
        │
        ├── wallpaper-rotate.sh  (timer, elke 10 min)
        ├── wallpaper-pick.sh    (Super+W)
        └── set-wallpaper.sh     (basis; ook vanaf de opdrachtregel)
                    │
                    ├─ 1. wal -i <foto>        → ~/.cache/wal/colors.json (pywal16)
                    ├─ 2. theme-gen.py         → themabestanden hieronder
                    ├─ 3. hyprctl hyprpaper    → wallpaper op alle monitors
                    └─ 4. Waybar/kitty/mako herladen + GTK- en KDE-thema toepassen
```

`theme-gen.py` leidt uit het pywal-palet een Material-achtig palet af (donkere
achtergrond, leesbare tekst op accentkleuren, vaste kleuren voor fouten en
waarschuwingen) en schrijft:

| Bestand | Voor |
| --- | --- |
| `~/.config/hypr/colors.conf` | Hyprland zelf (randen, schaduw) |
| `~/.config/hypr/hyprlock.conf` | gevuld vanuit `hyprlock.template.conf` |
| `~/.config/waybar/colors.css` | Waybar (`style.css` importeert dit) |
| `~/.config/wofi/colors.css`, `~/.config/wlogout/colors.css` | menu's en power-menu |
| `~/.config/mako/colors` | meldingen |
| `~/.config/kitty/hyprland-theme.conf` | kitty-kleuren en -opmaak |
| `~/.cache/hypr/palette.json` | het volledige palet, voor eigen scripts |

Kleuren zijn dus **nooit handmatig**: ze volgen de wallpaper. Wil je een andere
sfeer? Kies een andere foto.

### Eigen wallpapers toevoegen

```bash
cp ~/Pictures/mooi.jpg ~/.local/share/wallpapers/
```

`Super` + `W` laat ze allemaal met thumbnail zien; de timer pakt ze automatisch mee.
Een andere map gebruiken kan met `WALLPAPER_DIR=/pad/naar/foto's ./install.sh`.

## De wallpaper-timer

```bash
systemctl --user status  hyprland-wallpaper-rotate.timer   # status
systemctl --user list-timers                               # volgende wissel
systemctl --user stop    hyprland-wallpaper-rotate.timer   # pauzeren
systemctl --user start   hyprland-wallpaper-rotate.timer   # hervatten
systemctl --user disable --now hyprland-wallpaper-rotate.timer  # uit bij inloggen
```

De service heeft `ExecCondition=/usr/bin/pgrep -x Hyprland`: onder Plasma of qtile
gebeurt er dus niets. De timer van de qtile-opzet blijft ongemoeid en heeft
omgekeerd een controle op `qtile`, zodat ze elkaar nooit in de weg zitten.

## Vergrendelscherm (hyprlock)

Ubuntu 26.04 levert hyprlock **0.9.2**. Die versie crasht een paar seconden
nadat het scherm vergrendeld is (use-after-free in de async resource-gatherer,
opgelost in [hyprwm/hyprlock#961](https://github.com/hyprwm/hyprlock/pull/961),
uitgebracht in 0.9.3). Op deze machine is daarom een recente versie uit broncode
gebouwd en in `/usr/local/bin/hyprlock` gezet — die map gaat vóór `/usr/bin`, dus
`hyprlock`, `Super` + `L` en hypridle gebruiken automatisch de nieuwe versie.
Het pakket van Ubuntu blijft gewoon staan (voor updates en als reserve).

Opnieuw bouwen (bijvoorbeeld na een grote Ubuntu-upgrade):

```bash
./packages/build-hyprlock.sh          # bouwt v0.9.6
./packages/build-hyprlock.sh v0.9.5   # of een andere versie
```

`./update.sh` controleert zelf of er een nieuwere hyprlock-release is en bouwt
die zo nodig opnieuw.

Daarnaast is `/etc/pam.d/hyprlock` aangevuld: de pakketversie bevatte alleen
`auth`, waardoor hyprlock kan crashen bij `pam_end`
([hyprwm/hyprlock#953](https://github.com/hyprwm/hyprlock/issues/953)).
De originele versie staat als back-up in `/etc/pam.d/hyprlock.orig`.

## Mappenstructuur

```
Hyprland/
├── install.sh                  installatie + software
├── update.sh                   alles bijwerken (apt + externe bronnen)
├── hypr/
│   ├── hyprland.conf           compositor: look, binds, autostart, regels
│   ├── hypridle.conf           vergrendelen/sluimeren
│   ├── hyprpaper.conf          wallpaper-daemon
│   ├── hyprlock.template.conf  vergrendelscherm (thema wordt ingevuld)
│   └── scripts/                set-wallpaper, wallpaper-pick/rotate, theme-gen,
│                               screenshot, power-menu, lock, clipboard, …
├── waybar/, wofi/, mako/, wlogout/   configuraties van de bar en overlays
├── systemd/                    wallpaper-timer (service + timer)
├── packages/
│   ├── apt.txt                 te installeren software
│   └── build-hyprlock.sh       recente hyprlock bouwen (zie hierboven)
├── wallpapers/                 ophaalscript voor de voorbeeldset
└── docs/sneltoetsen.md         alle sneltoetsen
```

## Aanpassen

* **Sneltoetsen, animaties, regels** → `hypr/hyprland.conf`
* **Bar-indeling** → `waybar/config.jsonc` · **bar-opmaak** → `waybar/style.css`
* **Meldingen** → `mako/config` · **power-menu** → `wlogout/layout`
* **Paletafleiding** → `hypr/scripts/theme-gen.py`

Pas je iets aan in deze map, draai dan opnieuw `./install.sh`; kleuren zelf worden
bij elke wallpaperwissel automatisch bijgewerkt in `~/.config`.

## Probleemoplossing

| Verschijnsel | Oplossing |
| --- | --- |
| Klok in Waybar blijft leeg | `sudo locale-gen nl_NL.UTF-8` (daarna `Super` + `U`) |
| Vergrendelen mislukt of scherm valt terug | `./packages/build-hyprlock.sh` (Ubuntu's 0.9.2 crasht) |
| Geen kleuren na inloggen | `pipx install pywal16`, dan `Super` + `Shift` + `W` |
| Bar of menu ziet er oud uit | `Super` + `Shift` + `R` (kleuren) of `Super` + `U` (bar) |
| Iets werkt niet na een aanpassing | `Super` + `R` (Hyprland herladen) |
| Configuratie controleren | `Hyprland --verify-config -c ~/.config/hypr/hyprland.conf` |
| Logboek bekijken | `less "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log` |
| Spotify sluit tijdens een wallpaperwissel | Opgelost: Waybar herlaadt zijn kleuren nu zelf. Na een update één keer `pkill -x waybar; hyprctl dispatch exec waybar`. |

### Spotify en de wallpaperwissel

Spotify (Flatpak/CEF) beëindigt zichzelf met
`FATAL:dbus/bus.cc: D-Bus connection was disconnected` zodra zijn verbinding met
de sessiebus wegvalt. In de Flatpak-sandbox loopt die verbinding via
`xdg-dbus-proxy`. Bij iedere wissel stuurden zowel pywal als `set-wallpaper.sh`
een `SIGUSR2` naar Waybar. Waybar laat daarbij ongeveer 50 ms
`org.kde.StatusNotifierWatcher` vallen, waarna Spotify zijn tray-item opnieuw
aanmeldt — net de CEF-code die op een weggevallen bus aborteert.

Daarom doet de wissel nu het volgende:

* `wal` draait met `-e`, dus zonder pywal's eigen reload-hooks; `set-wallpaper.sh`
  herlaadt xrdb, kitty en mako zelf, precies één keer.
* Waybar krijgt geen signaal meer. `reload_style_on_change` volgt `colors.css`
  via de `@import` in `style.css`; die import gebruikt een gewoon pad in plaats
  van een `file://`-URL, omdat Waybar die URL niet naar een bestand herleidt en
  `colors.css` dan nooit in de gaten houdt.

## Verwijderen

```bash
systemctl --user disable --now hyprland-wallpaper-rotate.timer
rm -rf ~/.config/{hypr,waybar,wofi,mako,wlogout}
# en zet desgewenst de back-ups terug:
# mv ~/.config/hypr.bak-<datum> ~/.config/hypr
```
