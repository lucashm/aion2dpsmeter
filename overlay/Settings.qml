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
    readonly property int maxRows: adapter.maxRows
    readonly property int skillRows: adapter.skillRows
    readonly property string gameMonitor: adapter.gameMonitor
    // A monitor picked in edit mode; empty = follow the game.
    readonly property string pinnedMonitor: adapter.pinnedMonitor
    readonly property var widgets: adapter.widgets
    // What the meter and the history show per player: "both", "damage" or "dps".
    readonly property string meterMetric: adapter.meterMetric
    readonly property string historyMetric: adapter.historyMetric
    // Edit mode: snap dragged widgets to a grid of this many pixels.
    readonly property bool snapToGrid: adapter.snapToGrid
    readonly property int gridSize: adapter.gridSize

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
    function setSnapToGrid(on) { adapter.snapToGrid = on; }
    function setGridSize(px) { adapter.gridSize = Math.max(4, Math.min(64, px)); }
    function setMeterMetric(m) { adapter.meterMetric = m; }
    function setHistoryMetric(m) { adapter.historyMetric = m; }
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
            property int maxRows: 8
            property int skillRows: 10
            // The monitor the game was last seen on.
            property string gameMonitor: ""
            property string pinnedMonitor: ""
            property string meterMetric: "both"
            property string historyMetric: "both"
            property bool snapToGrid: true
            property int gridSize: 32
            // id -> { x, y, visible }
            property var widgets: ({})
        }
    }
}
