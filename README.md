# AION 2 DPS Meter for Linux

A damage meter for AION 2 that runs natively on Linux while the game runs through Steam/Proton.
It shows live combat numbers as small widgets on top of the game.

<!-- Screenshot: add docs/screenshot.png and uncomment the next line.
![The meter over the game](docs/screenshot.png)
-->

**Widgets**

- **DPS meter:** your party ranked by damage, with DPS, share and crit rate.
- **Skills:** damage, DPS, hits, crit and back-attack rate per skill, for you or any player.
- **Boss HP:** HP bar, damage dealt, fight timer and estimated time to kill.
- **Ping:** latency to the game server.
- **History:** every boss fight is saved, so you can look at it later.

It reads a copy of the game's network traffic, like other AION 2 meters do.
It never touches the game's memory or files.

## Supported desktops

| Desktop | Status |
| --- | --- |
| Hyprland | Works, tested |
| Sway, niri, river, Wayfire, labwc | Should work, not tested yet |
| KDE Plasma 6 | Works, but widgets can't hide on their own when you leave the game (use the hide key) |
| GNOME | Not supported (GNOME doesn't allow overlays like this) |
| X11 sessions | Not supported |

Only x86_64 Linux. Running the game inside gamescope is not supported, because nothing can draw on top of it.

## Install

You need **Quickshell** (it draws the widgets) and **setcap**:

| Distribution | Command |
| --- | --- |
| Arch, CachyOS, Manjaro | `sudo pacman -S quickshell libcap` |
| Fedora | `sudo dnf copr enable errornointernet/quickshell && sudo dnf install quickshell libcap` |
| Others | Quickshell: see [quickshell.org](https://quickshell.org). setcap is in `libcap2-bin` (Debian/Ubuntu) or `libcap` |

### From a release (easiest)

1. Download `aion2-meter-…-x86_64-linux.tar.gz` from the [Releases page](https://github.com/lucashm/aion2dpsmeter/releases).
2. Extract it and run the installer:

```bash
tar xzf aion2-meter-*-x86_64-linux.tar.gz
```

```bash
cd aion2-meter-*-x86_64-linux && ./install.sh
```

The installer asks for your password once, to let the meter capture network traffic.
Then it starts the meter, now and at every login.

### From source

You also need Rust, git, pkg-config and libpcap headers (`libpcap` on Arch, `libpcap-devel` on Fedora, `libpcap-dev` on Debian/Ubuntu).

```bash
git clone --recursive https://github.com/lucashm/aion2dpsmeter
```

```bash
cd aion2dpsmeter && ./scripts/install.sh
```

## Using it

Start the game. The widgets appear while the game window is focused.

- **Tray icon:** green means it's capturing, amber means it's waiting for the game, red means an error, grey means stopped.
  Left click opens edit mode. Right click has start/stop, history, reset and more.
  The icon follows your character's faction (Elyos or Asmodian), from the last character you logged in with.
- **Edit mode:** drag widgets to move them. They snap to a grid, and pink guides show when a widget lines up with the screen centre or another widget. Hold Shift to place freely.
  It also has settings: which widgets to show, size, opacity, damage or DPS columns, and which target to track.
  Click a player in the meter to see their skills.
- **App menu:** "AION 2 Meter" starts or stops it.

### Keybinds

**Hyprland:** add to your config, using keys you don't use already:

```lua
hl.bind("SUPER + SHIFT + D", hl.dsp.global("aion2meter:edit"))
hl.bind("SUPER + SHIFT + H", hl.dsp.global("aion2meter:history"))
hl.bind("SUPER + SHIFT + R", hl.dsp.global("aion2meter:reset"))
hl.bind("SUPER + SHIFT + O", hl.dsp.global("aion2meter:hide"))
hl.bind("SUPER + SHIFT + K", hl.dsp.global("aion2meter:next-player"))
```

With the older `hyprland.conf`, the first line looks like `bind = SUPER SHIFT, D, global, aion2meter:edit`.

**Other desktops:** bind a key to one of these commands in your desktop's keyboard settings:

| Command | What it does |
| --- | --- |
| `aion2-meter edit` | Edit mode (move widgets, settings) |
| `aion2-meter history` | Open or close the fight history |
| `aion2-meter reset` | Save the current fight and clear the meter |
| `aion2-meter hide` | Hide or show the widgets |
| `aion2-meter next-player` | Show the next player's skills |
| `aion2-meter toggle` | Start or stop the meter |

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
| Widgets never show | Check the tray icon is green while you play. On KDE, widgets don't follow the game window: use the hide key. |

The two lines for a VPN (put your interface name instead of `wg0`):

```ini
[Service]
ExecStart=
ExecStart=%h/.local/bin/aion2-meterd --iface wg0
```

See what the meter is doing:

```bash
journalctl --user -u aion2-meterd -f
```

**Reporting a bug:** open an issue with that log.
For tricky cases you can record your traffic with `aion2-meterd --record ~/aion2.pcap`.
That file contains your IP address and the names of players around you, so only share it if you're fine with that.

## How it works

- **`aion2-meterd`** captures the game's traffic (it is the only part with the capture permission), parses it, and keeps the combat numbers.
- **The overlay** (Quickshell) and **the tray icon** read those numbers through a local socket and run with no special permissions.
- Saved fights are in `~/.local/share/aion2-meter/fights`, and widget settings are in `~/.config/aion2-meter/overlay.json`.

## Credits and license

App icon by lucashm. The game protocol parser is [A2Tools DPS Meter](https://github.com/taengu/A2Tools-DPS-Meter) by taengu, used as a library (`third_party/a2tools`).

Copyright (C) 2026 lucashm. Licensed under the [GNU GPL v3.0](LICENSE), because A2Tools is GPL-3.0.

This is an unofficial fan project, not affiliated with NCSOFT. Like every AION 2 meter, it reads your own network traffic and doesn't change the game.
Whether third-party meters are allowed is up to NCSOFT's terms; use it at your own discretion.
