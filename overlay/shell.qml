//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

// AION 2 meter overlay for Wayland desktops with layer-shell. Run with:
// qs -p <this directory> (scripts/install.sh installs it as `qs -c aion2-meter`).
// On Hyprland it uses Hyprland's own events and keybinds; elsewhere the
// standard window list, and keybinds go through `aion2-meter <command>`.
ShellRoot {
    id: root

    property bool editMode: false
    property bool gameFocused: false
    // The game's window class under Proton is steam_app_<appid>; its title
    // starts with AION2.
    readonly property var gamePattern: /^(steam_app_3393110|aion2(\.exe)?)$/i

    readonly property bool onHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    // Without a window list (KDE), the game can't be told apart: widgets stay
    // up, and the toggle command hides them. The list fills in just after
    // start-up, so it is only judged empty after a moment.
    property bool windowListSettled: false
    readonly property bool canDetectFocus: onHyprland || !windowListSettled || ToplevelManager.toplevels.values.length > 0
    Timer {
        running: !root.onHyprland
        interval: 2000
        onTriggered: root.windowListSettled = true
    }
    readonly property bool alertsShown: editMode || gameFocused || !canDetectFocus || settings.alwaysShow
    readonly property bool showWidgets: alertsShown && (editMode || !settings.hideWidgets)

    // The screen the game is on: where it was last focused, else the
    // focused one.
    readonly property var gameScreen: {
        const name = settings.pinnedMonitor || settings.gameMonitor;
        const screens = Quickshell.screens;
        const found = screens.find(s => s.name === name);
        if (found) return found;
        const focused = root.onHyprland && Hyprland.focusedMonitor ? screens.find(s => s.name === Hyprland.focusedMonitor.name) : null;
        return focused || screens[0];
    }

    Settings { id: settings }
    MeterClient { id: client }

    Binding { target: Theme; property: "scale"; value: settings.uiScale }
    Binding { target: Theme; property: "opacity"; value: settings.uiOpacity }

    // `monitor` is given off Hyprland; on Hyprland it is the focused monitor.
    function onActiveWindow(cls, title, monitor) {
        const isGame = root.gamePattern.test(cls) || /^AION2\b/.test(title);
        root.gameFocused = isGame;
        if (!isGame) return;
        if (monitor !== undefined) settings.setGameMonitor(monitor);
        else if (Hyprland.focusedMonitor) settings.setGameMonitor(Hyprland.focusedMonitor.name);
    }

    Connections {
        target: root.onHyprland ? Hyprland : null
        function onRawEvent(event) {
            if (event.name === "activewindow") {
                const comma = event.data.indexOf(",");
                root.onActiveWindow(event.data.slice(0, comma), event.data.slice(comma + 1));
            } else if (event.name === "focusedmon" && root.gameFocused) {
                settings.setGameMonitor(event.data.split(",")[0]);
            } else if (event.name === "configreloaded") {
                // A reload drops binds made at runtime.
                root.boundKeys = [];
                root.applyShortcuts();
            }
        }
    }

    // The focused window at start-up.
    Process {
        running: root.onHyprland
        command: ["hyprctl", "activewindow", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const w = JSON.parse(text);
                    if (w && w.class !== undefined) root.onActiveWindow(w.class, w.title || "");
                } catch (e) {}
            }
        }
    }

    // Elsewhere: the standard window list (Sway, niri, river, Wayfire, labwc).
    function onToplevelFocus() {
        const t = ToplevelManager.activeToplevel;
        if (!t) {
            root.gameFocused = false;
            return;
        }
        root.onActiveWindow(t.appId, t.title, t.screens.length ? t.screens[0].name : "");
    }
    Connections {
        target: root.onHyprland ? null : ToplevelManager
        function onActiveToplevelChanged() { root.onToplevelFocus(); }
    }
    Connections {
        target: root.onHyprland ? null : ToplevelManager.activeToplevel
        function onTitleChanged() { root.onToplevelFocus(); }
    }
    Component.onCompleted: if (!onHyprland) onToplevelFocus()

    // ── widgets ─────────────────────────────────────────────────────────
    DpsMeter {
        id: meterWidget
        widgetId: "meter"
        client: client
        settings: settings
        screen: root.gameScreen
        editMode: root.editMode
        wanted: root.showWidgets
    }
    SkillBreakdown {
        id: skillsWidget
        widgetId: "skills"
        client: client
        settings: settings
        // Right under the meter, by pixels: scaling the gap would overlap them on small screens.
        defaultPos: Qt.point(24, meterWidget.defaultPos.y + 256)
        screen: root.gameScreen
        editMode: root.editMode
        wanted: root.showWidgets
    }
    BossBar {
        id: bossWidget
        widgetId: "boss"
        client: client
        settings: settings
        screen: root.gameScreen
        editMode: root.editMode
        wanted: root.showWidgets && (target !== null && (target.isBoss || hasHp))
    }
    StatusPill {
        id: statusWidget
        widgetId: "status"
        client: client
        settings: settings
        screen: root.gameScreen
        editMode: root.editMode
        wanted: root.showWidgets
    }
    HistoryPanel {
        id: historyWidget
        widgetId: "history"
        client: client
        settings: settings
        screen: root.gameScreen
        editMode: root.editMode
    }
    // The app window: pets, analytics.
    App {
        id: appWindow
        client: client
        settings: settings
        onOpenFight: id => {
            historyWidget.open = true;
            historyWidget.openFight(id);
        }
        onTestNotification: e => e.reminder ? eventAlertWidget.test(e.reminder) : cubeAlertWidget.push(e)
    }

    CubeAlert {
        id: cubeAlertWidget
        widgetId: "cubeAlert"
        client: client
        settings: settings
        screen: root.gameScreen
        editMode: root.editMode
        // While the game is focused, even with the widgets hidden; a test from
        // the app shows even while the game isn't focused.
        wanted: active && (root.alertsShown || appWindow.visible)
    }
    EventAlert {
        id: eventAlertWidget
        widgetId: "eventAlert"
        settings: settings
        gameRunning: !!(client.capture && client.capture.gameRunning)
        screen: root.gameScreen
        editMode: root.editMode
        wanted: active && (root.alertsShown || appWindow.visible)
    }

    PetFarm {
        id: petFarmWidget
        widgetId: "petFarm"
        client: client
        settings: settings
        screen: root.gameScreen
        editMode: root.editMode
        wanted: root.showWidgets && recent
    }

    EditorLayer {
        id: editor
        settings: settings
        client: client
        screen: root.gameScreen
        active: root.editMode
        // History isn't laid out: it opens on demand, centred.
        widgets: [meterWidget, skillsWidget, bossWidget, statusWidget, petFarmWidget, cubeAlertWidget, eventAlertWidget]
        onDone: root.editMode = false
    }

    // ── controls ────────────────────────────────────────────────────────
    // Hyprland's global shortcuts, e.g. hl.bind("SUPER + SHIFT + D", hl.dsp.global("aion2meter:edit")).
    // Elsewhere, bind `aion2-meter <command>` in the desktop's own settings.
    LazyLoader {
        active: root.onHyprland
        Scope {
            GlobalShortcut {
                appid: "aion2meter"
                name: "edit"
                description: "Toggle the meter's edit mode"
                onPressed: root.editMode = !root.editMode
            }
            GlobalShortcut {
                appid: "aion2meter"
                name: "history"
                description: "Open or close the fight history"
                onPressed: historyWidget.open = !historyWidget.open
            }
            GlobalShortcut {
                appid: "aion2meter"
                name: "analytics"
                description: "Open the app's analytics"
                onPressed: appWindow.show("analytics")
            }
            GlobalShortcut {
                appid: "aion2meter"
                name: "app"
                description: "Open the app"
                onPressed: appWindow.show("")
            }
            GlobalShortcut {
                appid: "aion2meter"
                name: "reset"
                description: "Save and reset the meter"
                onPressed: client.reset()
            }
            GlobalShortcut {
                appid: "aion2meter"
                name: "hide"
                description: "Hide or show the widgets"
                onPressed: settings.setHideWidgets(!settings.hideWidgets)
            }
            GlobalShortcut {
                appid: "aion2meter"
                name: "next-player"
                description: "Show the next player's skills"
                onPressed: root.focusNextPlayer()
            }
        }
    }

    // The shortcuts set in edit mode, bound only while the game has focus:
    // Ctrl/Alt combos would otherwise be taken from every other app. Not
    // while one is being recorded, so the editor gets the keys.
    // shortcut: hl.unbind drops any bind on the combo, the user's own too.
    property var boundKeys: []
    readonly property var shortcutKeys: onHyprland && gameFocused && !editor.recordingKeys
        ? [[settings.shortcutEdit, "edit"], [settings.shortcutHide, "hide"]]
            .filter(k => /^[A-Za-z0-9_]+( \+ [A-Za-z0-9_]+)*$/.test(k[0]))
            // ` is a dead key on some layouts: bind both of its names.
            .reduce((all, k) => all.concat(k[0].endsWith(" + grave") ? [k, [k[0].replace(/grave$/, "dead_grave"), k[1]]] : [k]), [])
        : []
    onShortcutKeysChanged: applyShortcuts()
    Component.onDestruction: if (boundKeys.length) Quickshell.execDetached(["hyprctl", "eval", boundKeys.map(k => `hl.unbind("${k}")`).join("\n")])
    function applyShortcuts() {
        const lua = boundKeys.map(k => `hl.unbind("${k}")`)
            .concat(shortcutKeys.map(k => `hl.bind("${k[0]}", hl.dsp.global("aion2meter:${k[1]}"), { description = "aion2meter:${k[1]}" })`));
        boundKeys = shortcutKeys.map(k => k[0]);
        if (lua.length) Quickshell.execDetached(["hyprctl", "eval", lua.join("\n")]);
    }

    // Binds left by an overlay stopped before it could unbind them (a killed
    // process runs no onDestruction), found by their description.
    Process {
        running: root.onHyprland
        command: ["hyprctl", "binds", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const mods = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]];
                    const stale = JSON.parse(text)
                        .filter(b => (b.description || "").startsWith("aion2meter:") && b.key)
                        .map(b => mods.filter(m => b.modmask & m[0]).map(m => m[1]).concat([b.key]).join(" + "));
                    root.boundKeys = root.boundKeys.concat(stale.filter(k => !root.boundKeys.includes(k)));
                    root.applyShortcuts();
                } catch (e) {}
            }
        }
    }

    function focusNextPlayer() {
        const ps = client.players;
        if (!ps.length) return;
        const cur = client.state ? client.state.skillsOf : null;
        const i = ps.findIndex(p => p.id === cur);
        const next = ps[(i + 1) % ps.length];
        client.focus(next.isLocal ? null : next.id);
    }

    // Also reachable without Hyprland binds: qs -c aion2-meter ipc call meter edit
    IpcHandler {
        target: "meter"
        function edit(): void { root.editMode = !root.editMode; }
        function history(): void { historyWidget.open = !historyWidget.open; }
        function analytics(): void { appWindow.show("analytics"); }
        function app(): void { appWindow.show(""); }
        function reset(): void { client.reset(); }
        function toggle(): void { settings.setHideWidgets(!settings.hideWidgets); }
        function nextPlayer(): void { root.focusNextPlayer(); }
        function mode(name: string): void { client.setTargetMode(name); }
        // A monitor name to pin the widgets there, or "follow" to follow the game.
        function monitor(name: string): void { settings.setPinnedMonitor(name === "follow" ? "" : name); }
    }
}
