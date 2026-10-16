//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// AION 2 meter overlay for Hyprland. Run with: qs -p <this directory>
// (scripts/install.sh links it as `qs -c aion2-meter`).
ShellRoot {
    id: root

    property bool editMode: false
    property bool gameFocused: false
    // Hidden with the toggle key, until pressed again.
    property bool hidden: false
    // The game's window class under Proton is steam_app_<appid>; its title
    // starts with AION2.
    readonly property var gamePattern: /^(steam_app_3393110|aion2(\.exe)?)$/i

    readonly property bool showWidgets: editMode || (!hidden && (gameFocused || settings.alwaysShow))

    // The screen the game is on: where it was last focused, else the
    // focused one.
    readonly property var gameScreen: {
        const name = settings.gameMonitor;
        const screens = Quickshell.screens;
        const found = screens.find(s => s.name === name);
        if (found) return found;
        const focused = Hyprland.focusedMonitor ? screens.find(s => s.name === Hyprland.focusedMonitor.name) : null;
        return focused || screens[0];
    }

    Settings { id: settings }
    MeterClient { id: client }

    Binding { target: Theme; property: "scale"; value: settings.uiScale }
    Binding { target: Theme; property: "opacity"; value: settings.uiOpacity }

    function onActiveWindow(cls, title) {
        const isGame = root.gamePattern.test(cls) || /^AION2\b/.test(title);
        root.gameFocused = isGame;
        if (isGame && Hyprland.focusedMonitor) settings.setGameMonitor(Hyprland.focusedMonitor.name);
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindow") {
                const comma = event.data.indexOf(",");
                root.onActiveWindow(event.data.slice(0, comma), event.data.slice(comma + 1));
            } else if (event.name === "focusedmon" && root.gameFocused) {
                settings.setGameMonitor(event.data.split(",")[0]);
            }
        }
    }

    // The focused window at start-up.
    Process {
        running: true
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

    EditorLayer {
        id: editor
        settings: settings
        client: client
        screen: root.gameScreen
        active: root.editMode
        widgets: [meterWidget, skillsWidget, bossWidget, statusWidget, historyWidget]
        onDone: root.editMode = false
    }

    // ── controls ────────────────────────────────────────────────────────
    // Bind these in Hyprland, e.g. hl.bind("SUPER + SHIFT + D", hl.dsp.global("aion2meter:edit"))
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
        name: "reset"
        description: "Save and reset the meter"
        onPressed: client.reset()
    }
    GlobalShortcut {
        appid: "aion2meter"
        name: "toggle"
        description: "Hide or show the widgets"
        onPressed: root.hidden = !root.hidden
    }
    GlobalShortcut {
        appid: "aion2meter"
        name: "next-player"
        description: "Show the next player's skills"
        onPressed: root.focusNextPlayer()
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
        function reset(): void { client.reset(); }
        function toggle(): void { root.hidden = !root.hidden; }
        function nextPlayer(): void { root.focusNextPlayer(); }
        function mode(name: string): void { client.setTargetMode(name); }
    }
}
