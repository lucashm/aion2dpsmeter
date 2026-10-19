import QtQuick
import Quickshell
import Quickshell.Io

// ~/.config/aion2-meter/overlay.json: widget positions and visibility,
// size, opacity. Edited from the overlay's edit mode, or by hand (the file
// is watched and reloaded).
Item {
    id: settings

    readonly property string path: Quickshell.env("AION2_METER_CONFIG") || (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/aion2-meter/overlay.json"

    readonly property real uiScale: adapter.scale
    readonly property real uiOpacity: adapter.opacity
    readonly property bool alwaysShow: adapter.alwaysShow
    // Widgets take the pointer outside edit mode, to be dragged while the
    // game's cursor is free (Alt). Off: they would block clicks to the game.
    readonly property bool moveInGame: adapter.moveInGame
    // In-game shortcuts, as Hyprland key combos ("CTRL + grave"); empty = none.
    readonly property string shortcutEdit: adapter.shortcutEdit
    readonly property string shortcutHide: adapter.shortcutHide
    readonly property int maxRows: adapter.maxRows
    readonly property int skillRows: adapter.skillRows
    readonly property string gameMonitor: adapter.gameMonitor
    // A monitor picked in edit mode; empty = follow the game.
    readonly property string pinnedMonitor: adapter.pinnedMonitor
    // Widgets hidden with the hide key or the tray (kept across restarts).
    readonly property bool hideWidgets: adapter.hideWidgets
    readonly property var widgets: adapter.widgets
    // Three saved layouts: each a copy of `widgets`, or null.
    readonly property var layouts: adapter.layouts
    // What the meter and the history show per player: "both", "damage" or "dps".
    readonly property string meterMetric: adapter.meterMetric
    readonly property string historyMetric: adapter.historyMetric
    // Edit mode: snap dragged widgets to a grid of this many pixels.
    readonly property bool snapToGrid: adapter.snapToGrid
    readonly property int gridSize: adapter.gridSize
    // Every name seen as the local player: "you" in analytics.
    readonly property var myNames: adapter.myNames
    // The app window's page: "pets", "map", "analytics" or "notifications".
    readonly property string appPage: adapter.appPage
    // The Pets page: its help card closed; the phase (the level farmed toward, 1-3); the
    // genuses and areas farmed; the sort.
    readonly property bool petsHelpHidden: adapter.petsHelpHidden
    readonly property string petsPhase: adapter.petsPhase
    readonly property var petsGenus: adapter.petsGenus
    readonly property var petsFarmIn: adapter.petsFarmIn
    readonly property string petsSort: adapter.petsSort
    // Notifications page: hidden cube alerts on.
    readonly property bool notifyCubes: adapter.notifyCubes
    // ...only while you have a Hidden Cube Key.
    readonly property bool cubesNeedKey: adapter.cubesNeedKey
    // ...with a chime for a cube nearby.
    readonly property bool cubeSound: adapter.cubeSound
    // Hourly event reminders: the Shugo Festival, the Dimensional Invasion,
    // how many minutes before, and a chime.
    readonly property bool notifyShugo: adapter.notifyShugo
    readonly property bool notifyInvasion: adapter.notifyInvasion
    readonly property int eventLead: adapter.eventLead
    readonly property bool eventSound: adapter.eventSound

    function widgetPos(id) {
        const w = widgets[id];
        return w && w.x !== undefined ? { x: w.x, y: w.y } : null;
    }
    function widgetVisible(id) {
        const w = widgets[id];
        return !w || w.visible !== false;
    }

    // `widgets` is replaced, never mutated, so bindings see the change.
    function updateWidget(id, change) {
        const all = Object.assign({}, adapter.widgets);
        all[id] = Object.assign({}, all[id] || {}, change);
        adapter.widgets = all;
    }
    function setWidgetPos(id, x, y) { updateWidget(id, { x: x, y: y }); }
    function setWidgetVisible(id, visible) { updateWidget(id, { visible: visible }); }
    function saveLayout(i) {
        const all = [0, 1, 2].map(n => adapter.layouts[n] || null);
        all[i] = JSON.parse(JSON.stringify(adapter.widgets));
        adapter.layouts = all;
    }
    function loadLayout(i) {
        const l = adapter.layouts[i];
        if (l) adapter.widgets = JSON.parse(JSON.stringify(l));
    }
    function resetLayout() {
        const all = {};
        for (const id in adapter.widgets) {
            if (adapter.widgets[id].visible === false) all[id] = { visible: false };
        }
        adapter.widgets = all;
    }
    function setScale(s) { adapter.scale = Math.round(Math.max(0.6, Math.min(2.0, s)) * 10) / 10; }
    function setOpacity(o) { adapter.opacity = Math.round(Math.max(0.2, Math.min(1.0, o)) * 10) / 10; }
    function setAlwaysShow(on) { adapter.alwaysShow = on; }
    function setMoveInGame(on) { adapter.moveInGame = on; }
    // One combo per shortcut: giving a combo to one takes it from the other.
    function setShortcut(name, combo) {
        if (combo && name !== "edit" && adapter.shortcutEdit === combo) adapter.shortcutEdit = "";
        if (combo && name !== "hide" && adapter.shortcutHide === combo) adapter.shortcutHide = "";
        if (name === "edit") adapter.shortcutEdit = combo;
        else if (name === "hide") adapter.shortcutHide = combo;
    }
    function setSnapToGrid(on) { adapter.snapToGrid = on; }
    function setGridSize(px) { adapter.gridSize = Math.max(4, Math.min(64, px)); }
    function setMeterMetric(m) { adapter.meterMetric = m; }
    function setHistoryMetric(m) { adapter.historyMetric = m; }
    function addMyName(name) {
        if (!adapter.myNames.includes(name)) adapter.myNames = adapter.myNames.concat([name]);
    }
    function setHideWidgets(on) { adapter.hideWidgets = on; }
    function setAppPage(page) { adapter.appPage = page; }
    function setPetsHelpHidden(on) { adapter.petsHelpHidden = on; }
    function setPetsPhase(phase) { adapter.petsPhase = String(phase); }
    function setPetsGenus(list) { adapter.petsGenus = list; }
    function setPetsFarmIn(list) { adapter.petsFarmIn = list; }
    function setPetsSort(key) { adapter.petsSort = key; }
    function setNotifyCubes(on) { adapter.notifyCubes = on; }
    function setCubesNeedKey(on) { adapter.cubesNeedKey = on; }
    function setCubeSound(on) { adapter.cubeSound = on; }
    function setNotifyShugo(on) { adapter.notifyShugo = on; }
    function setNotifyInvasion(on) { adapter.notifyInvasion = on; }
    function setEventLead(min) { adapter.eventLead = min; }
    function setEventSound(on) { adapter.eventSound = on; }
    function setPinnedMonitor(name) { adapter.pinnedMonitor = name; }
    function setGameMonitor(name) {
        if (name && name !== adapter.gameMonitor) adapter.gameMonitor = name;
    }

    FileView {
        id: file
        path: settings.path
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property real scale: 1.0
            property real opacity: 0.85
            property bool alwaysShow: false
            property bool moveInGame: false
            // The key above Tab: by the left hand and unbound in the game (Alt+letters open its tabs).
            property string shortcutEdit: "CTRL + grave"
            property string shortcutHide: "ALT + grave"
            property int maxRows: 8
            property int skillRows: 10
            // The monitor the game was last seen on.
            property string gameMonitor: ""
            property string pinnedMonitor: ""
            property bool hideWidgets: false
            property string meterMetric: "both"
            property string historyMetric: "both"
            property bool snapToGrid: true
            property int gridSize: 32
            // id -> { x, y, visible }
            property var widgets: ({})
            property var layouts: []
            property var myNames: []
            property string appPage: "pets"
            property bool petsHelpHidden: false
            property string petsPhase: "3"
            property var petsGenus: ["cogni", "fera", "natura", "varian", "special"]
            property var petsFarmIn: ["elyos", "asmodian", "abyss"]
            property string petsSort: "closest"
            property bool notifyCubes: true
            property bool cubesNeedKey: true
            property bool cubeSound: true
            property bool notifyShugo: true
            property bool notifyInvasion: true
            property int eventLead: 3
            property bool eventSound: true
        }
    }
}
