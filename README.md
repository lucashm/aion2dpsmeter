# aion2dpsmeter: AION 2 DPS meter for Linux / Hyprland

A native Linux combat meter for AION 2 running under Proton, with in-game widgets
drawn as Wayland layer-shell surfaces, built to work with Hyprland. It works like
questlog.gg's meter: it passively reads a copy of the game's network traffic.
It never touches the game's memory or files.

```
 AION2.exe (Proton) ── TCP :13328 ──▶ eno1
                                       │ libpcap (cap_net_raw, this binary only)
                                       ▼
 aion2-meterd (Rust) ── TCP reassembly ─▶ A2Tools parser ─▶ combat state
       │  /proc: which sockets are the game's            │ fights ▶ ~/.local/share/aion2-meter/fights
       ▼                                                 ▼
 $XDG_RUNTIME_DIR/aion2-meter.sock (JSON lines) ◀────────┘
       ▼
 Quickshell overlay (unprivileged) ─▶ wlr-layer-shell, overlay layer, click-through
```

## Widgets

| Widget | Shows |
| --- | --- |
| **DPS meter** | Party ranked by damage: DPS, share, crit rate, class colors, total. Your row stays visible below the cut |
| **Skills** | Your skills (or a picked player's): damage share, DPS, hits, crit %, back-attack % |
| **Boss HP** | Target HP bar, fight timer, estimated time to kill at the party's DPS |
| **Ping** | Four-bar latency, plus capture problems in plain words |
| **History** | Saved boss fights (written automatically when a fight ends or you change zones), with per-player results |

## How it handles Hyprland

Normal overlay windows fight a tiling compositor: they get tiled, sink behind
fullscreen games, need window rules, and can't be click-through on Wayland.
This overlay sidesteps all of that:

- Every widget is its own small **layer-shell surface on the `overlay` layer**,
  which Hyprland draws above fullscreen windows. No window rules, nothing tiled.
- The input region is **empty**, so clicks go to the game. Keyboard focus is
  never taken.
- **Edit mode** (a keybind) puts a fullscreen editor layer on top. In it you drag
  widgets, toggle them, change size and opacity, pick the target mode, and click
  a player to see their skills. Positions are saved in
  `~/.config/aion2-meter/overlay.json`.
- Widgets only show while the AION 2 window (`steam_app_3393110`) is focused,
  which is tracked through Hyprland's IPC. They appear on whichever monitor the
  game is on.
- **Not supported:** running the game inside **gamescope**. Nothing can draw
  over a nested compositor. Plain Proton, fullscreen or borderless, works.

## Install

Requires rust, quickshell, libpcap and libcap (all in CachyOS repos).

```bash
./scripts/install.sh
```

```bash
systemctl --user enable --now aion2-meterd aion2-meter-overlay
```

The script asks for sudo once, to run `setcap cap_net_raw,cap_net_admin=eip` on
`~/.local/bin/aion2-meterd`. Only the capture daemon gets that permission. Re-run
the script after every update: a rebuilt binary loses the capability.

To start or stop it later, use the **tray icon** (`aion2-meter-tray`, enable it with
`systemctl --user enable --now aion2-meter-tray`): left click opens edit mode or
starts the meter, right click has start/stop, history, reset, target mode and
start-at-login. The icon is green while capturing, amber while waiting for the
game, red on an error and grey when stopped. There is also **AION 2 Meter** in
the app launcher, and the command `aion2-meter [toggle|start|stop|restart|status|edit|history]`.

Then add binds to `~/.config/hypr/config/binds.lua`:

```lua
hl.bind("SUPER + SHIFT + D", hl.dsp.global("aion2meter:edit"))         -- move widgets / settings
hl.bind("SUPER + SHIFT + H", hl.dsp.global("aion2meter:history"))      -- fight history
hl.bind("SUPER + SHIFT + R", hl.dsp.global("aion2meter:reset"))        -- save + reset meter
hl.bind("SUPER + SHIFT + O", hl.dsp.global("aion2meter:toggle"))       -- hide/show widgets
hl.bind("SUPER + SHIFT + K", hl.dsp.global("aion2meter:next-player"))  -- cycle skill breakdown
```

The same actions work without binds:
`qs -c aion2-meter ipc call meter edit` (also `history`, `reset`, `toggle`,
`nextPlayer`, `mode bossTargets|lastHitByMe|mostDamage|allTargets|trainTargets`).

## The parser, and game patches

Protocol parsing is not reimplemented here. It comes from
[A2Tools DPS Meter](https://github.com/taengu/A2Tools-DPS-Meter) (GPL-3.0),
pinned as a git submodule in `third_party/a2tools` and used as a library
without its Tauri app. When a game patch breaks parsing and A2Tools fixes it,
update the submodule and reinstall:

```bash
git submodule update --remote third_party/a2tools
```

```bash
./scripts/install.sh
```

The Linux-specific parts are in `daemon/src`:

- `capture.rs`: libpcap capture.
- `tcp.rs`: real TCP reassembly, which reorders segments and drops retransmits.
- `game.rs`: finds the game and its sockets via `/proc`, so other connections
  can never be mistaken for the game.
- `dispatch.rs`: adapted from A2Tools' dispatcher.
- `meter.rs`, `history.rs`, `ipc.rs`: the overlay protocol.

## Debugging

```bash
journalctl --user -u aion2-meterd -f
```

Record your traffic while playing, then replay it offline (fast, or at the
original pace with `--realtime`):

```bash
aion2-meterd --record ~/aion2.pcap
```

```bash
aion2-meterd --pcap ~/aion2.pcap --print --socket /tmp/a2m-replay.sock
```

Work on the overlay without the game, using a fake fight:

```bash
python3 scripts/mock-daemon.py /tmp/a2m-mock.sock
```

```bash
AION2_METER_SOCKET=/tmp/a2m-mock.sock qs -p overlay
```

## A note on the game's rules

Like every AION 2 meter, this reads your own network traffic passively. It
doesn't modify the client, inject anything, or automate gameplay. Whether
third-party meters are allowed is up to NCSOFT's terms; use it at your own
discretion.

## License

GPL-3.0, because it links A2Tools' GPL-3.0 parser.
