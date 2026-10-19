# Windows UI technology decision

Research date: 2026-10-19. Baseline: PR #1, local commit `6344bb8`.
Status: [visual direction selected](windows-ui-design.md): C's visuals with
A's Questlog-like content. Production migration awaits a Windows performance
spike. No framework
comparison has been benchmarked in this repository.

## Recommendation

Use **Tauri 2 + React + TypeScript + Vite + CSS design tokens** for the main
companion window. Keep the **Rust capture daemon** and use a **small Rust/egui
overlay host** for the independent in-game widgets. This is an engineering
recommendation based on the existing code and desired interface, not a claim
that one framework wins every performance test.

The screenshots call for a persistent sidebar, dense tables, filters, history,
an overlay layout editor and eventually a map. HTML/CSS makes those layouts
and three distinctly styled prototypes straightforward to iterate on. Tauri
accepts web frontends and retains a Rust application core; Windows rendering
uses WebView2. It avoids shipping a separate browser engine in the app bundle,
but still runs browser processes and must be measured as such.
Sources: [Tauri architecture](https://v2.tauri.app/start/),
[Windows webview](https://v2.tauri.app/reference/webview-versions/).

For the widgets, retain the renderer already in the PR instead of immediately
introducing a webview for each health bar or timer. egui 0.31.1 exposes native
viewports, transparency, topmost level and mouse passthrough; its repaint API
can wake a sleeping UI only when needed. These capabilities make it a sensible
overlay starting point, **not proof of lower resource usage on this hardware**.
Sources: [egui viewport source, pinned version](https://raw.githubusercontent.com/emilk/egui/0.31.1/crates/egui/src/viewport.rs),
[repaint scheduling](https://raw.githubusercontent.com/emilk/egui/0.31.1/crates/egui/src/context.rs).

The tradeoff is two UI renderers and a small additional IPC boundary. Share
colors, spacing, typography and serialized layout settings; do not promise
shared UI components between CSS and egui. A single Tauri renderer for both
shell and widgets remains a reasonable simpler alternative **if** a measured
multi-window spike meets the budgets below. Tauri also exposes
[cursor passthrough](https://v2.tauri.app/reference/javascript/api/namespacewindow/#setignorecursorevents).

## Options considered

The suitability judgments below are specific to this repository. They are not
benchmark rankings.

| Stack | Fit for this app | Main cost or uncertainty | Decision |
| --- | --- | --- | --- |
| Existing eframe/egui | Rust throughout, existing capture integration, custom painting and native windows. A Questlog-like layout is possible. | More custom work for polished typography, complex application navigation and rich tables/maps; current default styling is not a framework ceiling. | Retain for overlays and as the working Windows baseline. [egui](https://github.com/emilk/egui) |
| Tauri 2 + TS frontend | CSS layout freedom with the existing Rust backend and native window APIs. | WebView2 deployment, browser process memory, lifecycle and transparency verification. Small download size does not establish low RAM usage. | Preferred companion shell. [Tauri](https://v2.tauri.app/start/) |
| Qt Quick 6 / QML | Strong custom visuals and a retained scene graph; Windows can use Direct3D. Existing Linux QML knowledge transfers. | New Qt packaging/toolchain and Rust integration; Quickshell-specific Linux code is not directly portable. | Strong alternative if consolidating both UIs around QML becomes a project goal. [Qt scene graph](https://doc.qt.io/qt-6/qtquick-visualcanvas-scenegraph.html) |
| WinUI 3 / XAML | First-party Fluent controls and Windows integration, using C# or C++. | Adds another implementation language and a Windows-only presentation stack around a Rust engine; custom overlay behavior still requires validation. | Choose if native Fluent conventions outrank cross-platform maintainability. [WinUI 3](https://learn.microsoft.com/en-us/windows/apps/winui/winui3/) |
| Electron | HTML/CSS freedom and mature desktop window APIs. | Bundled Chromium/Node stack; separate renderer per BrowserWindow. This app already has a Rust core and does not need a Node main process. | Not the preferred runtime for this scope. [Process model](https://www.electronjs.org/docs/latest/tutorial/process-model), [framework](https://github.com/electron/electron) |
| Slint | Declarative UI with direct Rust integration and Windows support. | Another UI language; map, chart and overlay needs should be proven with a focused spike. | Credible all-Rust-oriented alternative, with less immediate reuse of a web prototype. [Slint docs](https://docs.slint.dev/latest/docs/slint/) |

## Preserve the engine and Linux frontend

The current [Windows backend](../windows/src/backend.rs) owns one daemon child
and communicates through private newline-delimited JSON pipes. It already
handles the capture lock, Npcap checks, adapter discovery, replay, stderr log
and orderly shutdown. [Windows daemon IPC](../daemon/src/windows/ipc.rs)
exposes reset, target mode, focus, history, fight lookup and shutdown. The
[daemon loop](../daemon/src/main.rs) checks state every 200 ms and emits a
snapshot when changed or forced. These are source observations, not proposed
replacement services.

The migration seam should be presentation and supervision:

1. Extract the daemon session/model code from its egui repaint dependency.
   Preserve commands, event shapes, storage paths, capture ownership and
   shutdown behavior; introduce a narrow typed adapter for the new frontend.
2. Let the Tauri Rust core own that session and the overlay child. Feed the
   web UI through a typed channel and the overlay host through private pipes;
   the overlay host must not start a second daemon. Keep command replies and
   alerts reliable; coalesce obsolete state snapshots in bounded queues so a
   minimized window cannot stall pipe drainage.
3. Use a static frontend bundle, local assets and narrowly scoped native
   commands. Keep decoding, aggregation and file access in Rust. Request
   history details on demand; do not stream raw packets into JavaScript.
   Tauri documents channels for ordered streaming and cautions that its event
   bus is not designed for high throughput or low latency.
   [Rust-to-frontend IPC](https://v2.tauri.app/develop/calling-frontend/)
4. Keep the current [Linux workspace defaults](../Cargo.toml), daemon Unix
   socket, tray and Quickshell frontend intact. Linux QML imports
   `Quickshell.Wayland` and uses `WlrLayershell`, so a Windows Qt option would
   need a new window layer, not merely a new build target.
   [Linux overlay window](../overlay/OverlayWidget.qml)

The screenshots are design references, not a feature contract already supplied
by Windows. The current port supports live meter, fight history, pets and
settings; independent layouts, game-focus visibility, map, analytics and timers
need implementation work. Prototype data must be identified as sample data.
[Current support boundary](windows.md)

## Windows overlay requirements

- **Independent windows:** Use small borderless top-level HWNDs, one host
  process with several native viewports. In play mode they should be topmost,
  nonactivating and absent from the taskbar; edit mode temporarily permits
  drag/resize/input. `WS_EX_NOACTIVATE` and `SWP_NOACTIVATE` address activation;
  topmost ordering alone does not. Reapply policy after HWND recreation.
  [Window styles](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles),
  [SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)
- **Actual click-through:** CSS `pointer-events: none` only changes document
  hit testing. Use native passthrough and test clicks reaching the separate
  game process. Microsoft documents passthrough for layered windows with
  `WS_EX_TRANSPARENT`; `HTTRANSPARENT` alone routes hit testing through windows
  in the same thread. Renderer transparency and native hit testing must be
  validated together.
  [Layered windows](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features#layered-windows),
  [WM_NCHITTEST](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-nchittest)
- **Escape hatch:** Retain a system-wide unlock/hide shortcut and report
  registration conflicts. Preserve the current rule that click-through is
  disabled if hotkey registration fails and is not restored on startup.
  `RegisterHotKey` can fail for already registered combinations; the owner
  must handle its message loop and unregister during teardown.
  [Hotkey API](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey),
  [current behavior](../windows/src/backend.rs)
- **DPI and monitors:** Verify Per-Monitor V2 awareness; handle scale changes
  rather than applying the launch monitor's scale forever. Persist logical
  sizes with monitor identity and anchors; translate to physical pixels at
  the HWND boundary. Test 100/125/150/200%, negative screen coordinates,
  monitor removal and taskbar changes; clamp restored widgets to a visible
  work area. Microsoft documents PMv2 and `WM_DPICHANGED` requirements.
  [High-DPI guidance](https://learn.microsoft.com/en-us/windows/win32/hidpi/high-dpi-desktop-application-development-on-windows)
- **Game visibility:** Preserve borderless/windowed mode support; the current
  port does not promise exclusive fullscreen overlays. Track game focus,
  minimization and exit through native events rather than fast window scans.
  Verify actual AION2 behavior and other overlays together; no game injection
  is required by this architecture. [Current Windows limitations](windows.md)

## Proposed validation budgets — not measured results

After selecting the design, compare the current release build with the hybrid
spike using the same replay, machine, monitor setup and game settings. Record
CPU, GPU, private working set, startup time, UI frame times and capture health.
Account for **all** WebView2 child processes; report daemon and overlay costs
separately as well as combined totals. Use repeated runs and report variance.

| Scenario | Initial acceptance target |
| --- | --- |
| Shell visible with normal data | Warm usable window within 1 s; cold launch within 2 s; p95 UI frame time below 16.7 ms while scrolling. |
| State delivery | p95 daemon-event-to-visible-update below 100 ms; packet-to-display target below 350 ms, including the existing 200 ms snapshot interval. |
| Idle, no game | Combined UI processes below 1% total machine CPU averaged over 60 s, without continuous animation or needless repaint. |
| Overlay host, 8 small widgets | Below 100 MiB private working set for the host; repaint on changes, with short animation capped at 30 FPS. |
| Shell plus overlay UI | Initial combined UI memory budget 350 MiB, including WebView2; daemon measured separately. Validate release builds on the weakest supported reference PC. |
| Actual game | Aim for less than 2% median FPS loss and less than 5% regression in 1% low FPS versus the daemon-only baseline; results must exceed run-to-run noise before attributing a difference. |
| Long session | No dropped command replies, unbounded queues or sustained memory growth over a two-hour replay. Closing/minimizing the shell leaves overlays correct. |

These are provisional product budgets, not framework guarantees. If the hybrid
misses them, first profile renderer activity, hidden-window updates and IPC.
Measure whether hiding or destroying the shell webview releases sufficient
resources while the Rust core and overlays continue. A prototype in a browser
cannot establish native startup, overlay correctness or game performance.

## Distribution and licenses

Tauri adds a WebView2 runtime requirement. Prefer Evergreen with a presence
check and supported installer bootstrapper; provide a documented offline path.
Windows 11 includes the runtime, but Microsoft still recommends detecting its
presence. A portable ZIP needs its own prerequisite handling. Evergreen
updates independently, so test the UI against runtime updates rather than
assuming an installed version stays fixed.
[Microsoft distribution guidance](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution),
[Tauri installer options](https://v2.tauri.app/distribute/windows-installer/)

The project is already GPL-3.0-only ([Windows manifest](../windows/Cargo.toml)).
Retaining a permissively licensed UI dependency does not change that:
[egui is MIT/Apache-2.0](https://github.com/emilk/egui),
[Tauri uses MIT or MIT/Apache-2.0 as applicable](https://github.com/tauri-apps/tauri#licenses),
[Electron is MIT](https://github.com/electron/electron#license) and
[WinUI is MIT](https://github.com/microsoft/microsoft-ui-xaml).
Ship the required notices and check transitive dependencies and bundled fonts.
Qt offers LGPLv3/GPLv3/commercial licensing, with some GPL-only modules;
its module and distribution obligations need to be accounted for, but GPLv3
is not inherently a blocker for this GPL project.
[Qt licensing](https://doc.qt.io/qt-6/licensing.html)
Slint offers GPLv3, royalty-free desktop/mobile/web and commercial options;
GPLv3 is the natural candidate here, with the selected version's terms checked
at adoption. [Slint license](https://github.com/slint-ui/slint/blob/master/LICENSE.md?plain=1)

Keep Npcap separately installed as in PR #1. A UI toolkit change does not
grant permission to redistribute its driver/runtime.
[Npcap redistribution terms](https://npcap.com/oem/redist)

## Next implementation step

The selected design is C's visuals with A's content and navigation. Build one
real native slice: live data, a single detached meter, layout edit/unlock, mixed-DPI moves,
minimize-to-tray and shutdown. That experiment resolves the largest remaining
uncertainties: transparent-window behavior on the target GPU, WebView2 memory
when the shell is hidden, overlay-host complexity, and measured game impact.
Keep production migration separate from the prototype comparison.
