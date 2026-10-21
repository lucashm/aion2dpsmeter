# Daevalog

An AION 2 companion app: a damage meter, pet tracker, map and alerts that run natively on Linux while the game runs through Steam/Proton.
It shows live combat numbers as small widgets on top of the game, plus an app window for everything else.

**Windows 10/11 x64:** a Questlog-style companion with live DPS, skills,
pet collection, fight history, native overlay widgets, reminders and a system
tray is also available. Install Npcap and WebView2 separately and extract the
Windows ZIP. See the [Windows setup, features and
build guide](docs/windows.md). The instructions below describe the Linux app.

<!-- Screenshot: add docs/screenshot.png and uncomment the next line.
![The meter over the game](docs/screenshot.png)
-->

**Widgets**

- **DPS meter:** your party ranked by damage, with DPS, share and crit rate.
- **Skills:** damage, DPS, hits, crit and back-attack rate per skill, for you or any player.
- **Boss HP:** HP bar, damage dealt, fight timer and estimated time to kill.
- **Ping:** latency to the game server.
- **History:** every boss fight is saved, so you can look at it later.
- **App window** (tray → Open app): a full **Pets** tracker, a **Map** of where the pets you still need spawn, and **Analytics**, your past runs in one table by player, class, boss or single run, with averages, bests and trends.

It reads a copy of the game's network traffic, like other AION 2 meters do.
It never touches the game's memory or files.

## Supported desktops

| Desktop | Status |
| --- | --- |
| Hyprland | Works, tested |
| Sway, niri, river, Wayfire, labwc | Should work, not tested yet |
| KDE Plasma 6 | Works, but widgets can't hide on their own when you leave the game (use Alt+` or the tray icon) |
| GNOME | Not supported: GNOME doesn't implement layer-shell, which the widgets need. Feel free to try, and [let us know how it goes](https://github.com/lucashm/daevalog/issues) |
| X11 sessions | Not supported |

It needs a Wayland session with layer-shell (what panels and docks use), on x86_64. Running the game inside gamescope is not supported, because nothing can draw on top of it.

## Install

### From a release (easiest)

1. Except on Arch, CachyOS, Manjaro and Fedora (where the installer takes care of everything in step 3), install **Quickshell** first: see [quickshell.org](https://quickshell.org).
2. Download `aion2-meter-…-x86_64-linux.tar.gz` from the [Releases page](https://github.com/lucashm/daevalog/releases).
3. Extract it and run the installer:

```bash
tar xzf aion2-meter-*-x86_64-linux.tar.gz
```

```bash
cd aion2-meter-*-x86_64-linux && ./install.sh
```

The installer checks what's missing and offers to install it with your package manager, showing the command first. It asks for your password for that and for `setcap`, which lets the capture daemon read network traffic without running as root.

What it needs, if you'd rather install it yourself:

| | Arch, CachyOS, Manjaro | Fedora | Debian, Ubuntu |
| --- | --- | --- | --- |
| Quickshell (draws everything) | `quickshell` | `quickshell` (COPR `errornointernet/quickshell`) | [quickshell.org](https://quickshell.org) |
| setcap | `libcap` | `libcap` | `libcap2-bin` |
| Qt image formats (the app's map and pet portraits) | `qt6-imageformats` | `qt6-qtimageformats` | `qt6-image-formats-plugins` |
| curl (downloads the pet map) | `curl` | `curl` | `curl` |
| Noto Sans (the app's text) | `noto-fonts` | `google-noto-sans-fonts` | `fonts-noto-core` |

Only Quickshell and setcap are required; without the others the meter runs, minus the feature in parentheses.
Everything installs into your home directory (`~/.local/bin`, `~/.config`, `~/.local/share`) and runs as systemd user services, started now and at every login.

### From source

You need git, plus what's above and Rust, pkg-config and libpcap headers; the installer offers to install those too (`rust pkgconf libpcap` on Arch, `cargo pkgconf libpcap-devel` on Fedora, `cargo pkgconf libpcap-dev` on Debian/Ubuntu).

```bash
git clone --recursive https://github.com/lucashm/daevalog
```

```bash
cd daevalog && ./scripts/install.sh
```

## Using it

Start the game. The widgets appear while the game window is focused.

- **Tray icon:** green means it's capturing, amber means it's waiting for the game, red means an error, grey means the widgets are hidden (or the meter is stopped).
  Left click shows or hides the widgets. Right click has Customize, history, Open app, reset and more.
  The icon follows your character's faction (Elyos or Asmodian), from the last character you logged in with.
- **Customize** (tray menu or Ctrl+`): drag widgets to move them. They snap to a grid, and pink guides show when a widget lines up with the screen centre or another widget. Hold Shift to place freely. Esc or Done to finish.
  It also has settings: which widgets to show, which monitor, which target to track, damage or DPS columns, shortcuts, size and opacity.
  Click a player in the meter to see their skills.
- **Layouts:** three slots in Customize. Save stores where the widgets are and which are shown; Layout 1–3 puts them back, and the one on screen is highlighted. Reset layout goes back to the default, which fits any 16:9 or 21:9 screen.
- **Drag widgets in game:** an option in Customize, off by default. With it on, hold Alt (the game's free cursor) and drag a widget to move it, or click a player in the meter for their skills. It's off by default because the widgets then take clicks meant for the game under them, which gets in the way if you play with a free mouse.
- **App:** tray → Open app, or `aion2-meter app`. An ordinary window, so it works with the game closed too.
  - **Pets:** every pet with your level and souls, grouped into what's still needed for the level you're farming toward (Lv. 3 unless you pick Lv. 1 or 2), what's done, and what you don't farm. Pick the level, the genuses and the areas you farm on the left; it also shows each genus's collection and insight level, and your next collection reward. Levels the meter worked out from souls show "Est." until the game confirms them. Pet levels come from the game at login and on every Kibelisk teleport, so if the meter started after you logged in, teleport once.
  - **Map:** where pets spawn on Verteron, Altgard and the Abyss (Chaotic Lower Reshanta): each spawn area shows the pet's portrait in a ring of its genus's colour. The Abyss has no exact spawn points, so its pets sit in the middle of the zones their monsters are in. The panel on the left picks the map, the pets still needed or all pets, the genuses, and lists the pets with their souls left: untick one to hide it, click one to zoom to its spawns. A pet row's map icon on the Pets page opens the map on just that pet (✕ in the panel clears it). Scroll to zoom, drag to move, and hover a portrait for a card with the pet's level and souls, its spawns there, and the monsters that drop it on that map with their zone and nearest teleport. **Cube spots (partial)** (under Layers) shows some of the spots where hidden cubes can spawn on Verteron and Altgard, as small diamonds. A cube spawns on only a few of a map's many spots at a time, and Arkive lists just part of them (none for the Abyss). The map downloads once (about 10 MB) the first time you open the app.
  - **Analytics:** your past runs, as above. Clicking a run opens it in the fight history over the game.
  - **Notifications:** turns each in-game alert on or off, with a button to show a test one: hidden cubes and event reminders.
- **Hidden cube alerts:** a banner at the top of the screen when a hidden cube comes within about 100 m (the game tells nearby players), and when someone else starts opening it or opens it, with their name. The nearby banner stays up while the cube is in range, until it's opened or you move away, and its distance updates whenever the game sends your position: often in fights, every few seconds to half a minute while just walking (it says how old the distance is once it's 5 seconds old). A short chime plays with the nearby alert (through PipeWire's `pw-play` or PulseAudio's `paplay`). By default the nearby alert only shows while you have a Hidden Cube Key: the meter reads your keys from your bag at login and takes off the ones you use (until it has seen your bag, for example when it started after you logged in, it alerts anyway). Move the banner in Customize; turn it off, or the key check, on the app's Notifications page. Every cube the meter sees is also saved with its game position in `~/.local/share/aion2-meter/cube-spots.json`, building up the spots where cubes spawn in the places you play. The Map page shows them under **Cubes seen by the meter**, and a cube that's in range right now pulses on the map for 5 minutes or until it's opened. Positions are exact on Altgard; Verteron uses the same conversion but hasn't been checked.
- **Event reminders:** a banner with a countdown and a chime 1, 3, 5 or 10 minutes before the Shugo Festival (every hour at :00) and the Dimensional Invasion (every hour at :30: Beritra Air Raid, Accursed Sword or Incursion of the Spirits), staying up for a minute after it starts. The times are the game's server clock (UTC+9, the same for every global region), from community timers like [wikily.gg](https://wikily.gg/aion-2/bosses/timer), since NCSOFT doesn't publish them. Turn each one on or off, pick how early, and turn the sound off on the Notifications page; move the banner in Customize.
- **Pet souls widget:** while you pick up souls for pets that aren't full, it shows up to 5 of them, the last farmed first: each pet's portrait, level, souls to the next level and to level 3, souls per minute, and how long both take at that rate. Each pet goes away 5 minutes after its last soul.
- **App menu:** "Daevalog" starts or stops it. So does `aion2-meter toggle`.

### Shortcuts

| Keys | What it does |
| --- | --- |
| **Ctrl+`** | Open Customize |
| **Alt+`** | Hide or show the widgets |

**On Hyprland** the meter sets these up by itself, only while the game has focus, so the keys stay free in your other apps. Change or clear them in Customize → Shortcuts.

**On other desktops**, add them in your desktop's keyboard settings with the commands below (`Ctrl+grave` → `aion2-meter edit`, `Alt+grave` → `aion2-meter hide`). Those work in every app, so pick other keys if you need these ones elsewhere.

### Commands

Everything the meter does is also an `aion2-meter` command. Run it from a terminal, or bind it to a key in your desktop's keyboard settings (KDE: System Settings → Keyboard → Shortcuts; Sway: `bindsym Ctrl+grave exec ~/.local/bin/aion2-meter edit`).

| Command | What it does |
| --- | --- |
| `aion2-meter edit` | Open Customize (move widgets, settings) |
| `aion2-meter hide` | Hide or show the widgets |
| `aion2-meter history` | Open or close the fight history |
| `aion2-meter app` | Open the app |
| `aion2-meter analytics` | Open the app on Analytics |
| `aion2-meter reset` | Save the current fight and clear the meter |
| `aion2-meter next-player` | Show the next player's skills |
| `aion2-meter start`, `stop`, `restart` | Start, stop or restart the meter |
| `aion2-meter toggle` | Start it if it's stopped, stop it if it's running |
| `aion2-meter status` | Show the state of its services |

It's installed in `~/.local/bin`. If a launcher or shortcut can't find it, use the full path, `~/.local/bin/aion2-meter`.

## Update

Download the new release and run its `install.sh` again. From source:

```bash
git pull && git submodule update && ./scripts/install.sh
```

Game patches sometimes change the network data and break the numbers.
The fix usually comes from the A2Tools parser this meter uses (see below), and then in a new release.

## Uninstall

Run `uninstall.sh` (in the release folder, or `scripts/` in the source). It keeps your saved fights and settings.
Add `--purge` to delete those too.

## Problems

| What you see | What to do |
| --- | --- |
| Tray icon red, "no capture permission" | Run the installer again. |
| Stays on "finding game traffic" | If you use a VPN, capture on its network interface (find its name with `ip link`): run `systemctl --user edit aion2-meterd`, add the two lines below, save, then `systemctl --user restart aion2-meterd`. |
| Widgets never show | Check the tray icon is green while you play, and that the services run: `aion2-meter status`. On KDE, widgets don't follow the game window: use Alt+`. |

The two lines for a VPN (put your interface name instead of `wg0`):

```ini
[Service]
ExecStart=
ExecStart=%h/.local/bin/aion2-meterd --iface wg0
```

See what the meter is doing (the overlay's log is `aion2-meter-overlay`, the tray's `aion2-meter-tray`):

```bash
journalctl --user -u aion2-meterd -f
```

**Reporting a bug:** open an issue with that log.
For tricky cases you can record your traffic with `aion2-meterd --record ~/aion2.pcap`.
That file contains your IP address and the names of players around you, so only share it if you're fine with that.

## How it works

- **`aion2-meterd`** captures the game's traffic (it is the only part with the capture permission), parses it, and keeps the combat numbers.
- **The overlay** (Quickshell, on the layer-shell overlay layer) and **the tray icon** (StatusNotifierItem) read those numbers through a local Unix socket and run with no special permissions.
- All three are systemd user services: `aion2-meterd`, `aion2-meter-overlay` and `aion2-meter-tray`.
- Saved fights are in `~/.local/share/aion2-meter/fights`, and widget settings are in `~/.config/aion2-meter/overlay.json`.

## Credits and license

App icon by lucashm. The game protocol parser is [A2Tools DPS Meter](https://github.com/taengu/A2Tools-DPS-Meter) by taengu, used as a library (`third_party/a2tools`). Pet names, soul drops and the pet soul packets come from its [Pet Soul Tracker](https://github.com/taengu/A2Tools-Plugins/tree/main/plugins/pet-souls) plugin (GPL-3.0); `scripts/update-pet-data.py` refreshes `overlay/data/pets.json` from it. The pet map's tiles, spawn points and pet portraits come from [Arkive](https://github.com/arkive-games/arkive) by tc-imba (data CC BY-NC 4.0), downloaded by `overlay/fetch-map.sh`. Collection rewards are from [wikily.gg](https://wikily.gg/aion-2/genus-insight). The hidden cube packets were worked out by [aion2-cube-radar](https://github.com/dr89mh/aion2-cube-radar) (GPL-3.0).

Copyright (C) 2026 lucashm. Licensed under the [GNU GPL v3.0](LICENSE).

This is an unofficial fan project, not affiliated with NCSOFT. Like every AION 2 meter, it reads your own network traffic and doesn't change the game.
Whether third-party meters are allowed is up to NCSOFT's terms; use it at your own discretion.

AION 2 and its game data and art are © NCSOFT. The class icons come from A2Tools; skill icons are loaded from NCSOFT's CDN while the meter runs.
