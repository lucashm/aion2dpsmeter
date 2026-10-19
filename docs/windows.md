# Daevalog for Windows

Windows 10/11 **x64** is supported by Daevalog's native Rust/egui desktop frontend.
It uses the same capture decoding, TCP reassembly, A2Tools parser, DPS
calculation and fight/pet persistence as the Linux daemon. No browser,
Quickshell, WSL, systemd or Rust installation is needed to run a release.

## Desktop UI design preview

The selected Questlog-inspired composition is available in the
[desktop design preview](../windows/prototype/README.md): Command's visuals
with Obsidian's content and labeled navigation. Start it with
`node scripts/preview-desktop.mjs`.
The preview uses fictional in-memory data and does not replace the native app.
The [technology evaluation](windows-ui-stack.md) compares Windows UI stacks
and proposes a rich Tauri companion with lightweight Rust overlays, subject to
native performance validation.

## Install and play

1. Install the current **Npcap** from [npcap.com](https://npcap.com/#download).
   Enable **Install Npcap in WinPcap API-compatible Mode**. Raw 802.11/monitor
   mode is not needed for Ethernet or normal Wi-Fi capture. If another meter
   already installed Npcap with compatible mode enabled, reuse it.
2. Download `aion2-meter-<version>-x86_64-windows.zip` from
   [Releases](https://github.com/lucashm/daevalog/releases), or download the
   `aion2-meter-windows` artifact from a successful Windows CI run on this PR.
   GitHub wraps CI artifacts in another ZIP: extract both ZIPs.
3. Extract the **whole** package to a writable folder and open
   `aion2-meter-windows.exe`. Keep `aion2-meterd.exe` and `data/` beside it.
   These are unsigned builds; Windows may show a publisher/SmartScreen prompt.
4. Start AION 2 and enter combat. Capture starts automatically; the status
   changes from waiting for `AION2.exe`, to finding traffic, to capturing.
5. Enable **Always on top** and optionally **Compact** to keep the meter above
   the game. Use the game's **borderless/windowed** mode; an ordinary desktop
   window cannot overlay exclusive fullscreen.

The display name is **Daevalog**. Binary, archive and data-directory names keep
`aion2-meter`, matching upstream's compatibility policy. Window preferences
retain the existing `AION 2 Meter` storage ID, so renaming the app preserves
your settings and saved data.

The app normally runs without elevation. If Npcap was installed with capture
restricted to Administrators, either run the meter as Administrator or change
that Npcap option. The meter does not install drivers or change system settings.

## Controls and features

- **Live meter:** ranked player DPS, damage, contribution and crit rate; click
  a player to see skills, DPS, hits, crit and back-attack rates. **My skills**
  restores your own breakdown. Boss HP and ping appear when available.
- **Target:** boss encounters, all targets, or your last target.
- **Save & reset:** saves the current boss fight before clearing the meter.
- **Fight history:** the latest 100 fights, player totals and per-player skills.
- **Pets:** collection levels and soul points, using the same per-server data
  as Linux. Teleport at a Kibelisk if capture started after login.
- **Hidden cubes:** a text alert when a cube is near or being opened.
- **Ctrl+Alt+M:** toggle click-through. This also enables Always on top. Press
  it again to operate the app. Click-through is disabled if the shortcut could
  not be registered, and is never restored automatically on startup.
- **Settings:** choose an Npcap adapter, restart capture, or replay a `.pcap`
  file at its recorded pace. Auto matches the local IP selected by the default
  IPv4 route; a UDP route lookup sends no traffic. Select the VPN adapter
  explicitly when needed. Apply/restart after changing adapter or replay path.
- **Close:** saves the current fight and stops its child capture process.
  Starting a second capture in this user's desktop app is blocked.

This first Windows frontend focuses on the meter and saved fights. Linux's
separate movable widgets, automatic game-focus visibility, system tray,
layout editor, pet spawn map, analytics page, event timers and audio alerts
are not yet available in the Windows frontend. Linux retains those features.

## Why Npcap?

The meter needs a passive copy of the game's TCP payloads. Windows process
and socket enumeration identifies the game's connections but does not provide
their payloads. The existing engine uses libpcap; **Npcap is the maintained
Windows implementation of that capture API**.

Windows raw sockets are a possible different implementation, but require
administrator privileges and introduce a separate capture path and protocol
limitations. Windows Filtering Platform or WinDivert would require a different
driver/backend. Npcap reuses the proven parser input and supports ordinary
Ethernet/Wi-Fi and selectable VPN adapters. It is required by this port for
both live capture and pcap replay; it is not a universal requirement for every
possible Windows meter implementation.

Npcap is installed **separately**, not bundled, downloaded, silently installed
or upgraded by the app. The free Npcap license does not generally grant
third-party redistribution; bundling it would require an appropriate OEM
license. The build generates a small MSVC **import library** from the public
API names in `windows/wpcap.def`. This contains no Npcap runtime code or
driver and avoids requiring the Npcap SDK or driver on build/CI machines.

References: [Npcap developer guide](https://npcap.com/guide/npcap-devguide.html),
[Npcap installation options](https://npcap.com/guide/npcap-users-guide.html),
[Npcap redistribution](https://npcap.com/oem/redist),
[Windows raw socket constraints](https://learn.microsoft.com/en-us/windows/win32/winsock/tcp-ip-raw-sockets-2).

## Files and troubleshooting

Capture data is in `%LOCALAPPDATA%\aion2-meter\`: `fights/`, `pets.json`,
`cube-spots.json`, `capture.lock` and `capture.log` (replaced on capture start).
Window position and preferences are stored by eframe under
`%APPDATA%\AION 2 Meter\data\`. Closing the app also releases the capture lock.
To uninstall, delete the extracted package; keep these data folders to retain
history, or remove them to purge it. Npcap is shared with other applications
and should only be uninstalled separately when no longer needed.

| Symptom | Action |
| --- | --- |
| Npcap missing / `wpcap.dll` missing / exit `0xc0000135` | Install x64 Npcap with WinPcap compatibility enabled; restart the app. Do not download DLLs from third-party DLL sites. |
| Waiting for the game | Start the actual `AION2.exe` client, not just its launcher. |
| Finding game traffic | Enter combat; check Settings → adapter, especially with a VPN; restart capture after changing networks. |
| Capture permission error | Check Npcap's administrator-only installation option. |
| Window behind game | Enable Always on top and use borderless/windowed game mode. |
| Window ignores clicks | Press Ctrl+Alt+M to turn click-through off. |
| Missing skills/NPC names | Re-extract the entire ZIP, including `data/`. |
| Capture error | Read `%LOCALAPPDATA%\aion2-meter\capture.log`; report the error and adapter description. |

For a diagnostic recording, stop capture in the app, then run from PowerShell
inside the extracted directory (replace the adapter name using the list):

```powershell
./aion2-meterd.exe --list-interfaces
./aion2-meterd.exe --stdio --iface '\Device\NPF_{YOUR-ADAPTER-GUID}' --record "$env:USERPROFILE/Desktop/aion2.pcap"
```

Keep that terminal open; enter `{"cmd":"shutdown"}` to save and exit. Captures
include IP addresses and player names, so review them before sharing.

## Build and validate

Install current stable Rust (MSVC toolchain) and Visual Studio
2022 Build Tools with **Desktop development with C++** and the Windows SDK.
Npcap is only needed to *run* the daemon, not to build or run unit tests.

```powershell
git clone --recursive https://github.com/lucashm/daevalog
cd daevalog
./scripts/prepare-windows.ps1
cargo fmt --check -p aion2-meterd -p aion2-meter-windows
cargo clippy --locked --all-targets --no-deps -p aion2-meterd -p aion2-meter-windows -- -D warnings
cargo test --locked -p aion2-meterd -p aion2-meter-windows
./scripts/package-windows.ps1 -Version dev
```

The ZIP and its SHA-256 checksum are in `dist/`. Windows uses a static CRT;
the Visual C++ redistributable is not needed by these executables. For debug
development, build both crates and run `target/debug/aion2-meter-windows.exe`.
With Npcap installed, run `python scripts/test-daemon.py` after that build
for private-pipe command, replay, error and shutdown smoke tests.

For visual QA, build the frontend with `--features ui-smoke` and set
`AION2_METER_SCREENSHOT` to an absolute `.png` path before launching it. The
app captures the renderer's next completed frame and closes cleanly. Optional
`AION2_METER_SMOKE_TAB` selects 0 (live), 1 (history), 2 (pets), or 3 (settings);
`AION2_METER_SMOKE_STATE` loads a daemon state JSON fixture for the live meter.
These hooks are excluded from normal builds and release packages.

Linux's default workspace members remain `daemon` and `tray`; the Windows
frontend dependencies are Windows-only. Linux's Unix socket protocol,
`/proc` process/route discovery, QML overlay, tray, installer and systemd
units remain on their existing paths. CI keeps the Linux checks and adds an
independent Windows build, tests and downloadable ZIP. Tagged releases publish
both platforms' archives and checksums together.
