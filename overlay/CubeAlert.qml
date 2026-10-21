import QtQuick
import Quickshell

// Hidden cube alerts at the top centre: a cube in range (the game sends it
// from about 100 m), someone opening it, and it being opened. Up to three
// at a time, the newest on top. A cube in range stays up, its distance
// updated whenever the game sends your position, until it's opened or out
// of range (2 minutes at most); the others go after a few seconds. Turned
// off on the app's Notifications page.
OverlayWidget {
    id: alerts

    required property var client
    title: "Hidden cube alerts"
    // Takes clicks while a notification is up, for its ✕.
    interactive: active
    readonly property int width_: Math.round(380 * Theme.scale)
    defaultPos: Qt.point(Math.round((screen ? screen.width : 2560) / 2 - width_ / 2), Math.round(150 * hud))

    // { key, title, note, until } and for a cube in range { cube, distance, at, keys }, the newest first.
    property var shown: []
    property int count: 0
    property real now: Date.now()
    readonly property bool active: shown.length > 0

    // A cube in range's line: its distance and how old that is, your keys.
    function nearNote(a) {
        const age = Math.round((now - a.at) / 1000);
        return (a.distance != null ? "About " + a.distance + " m away" + (age >= 5 ? "  (" + age + " s ago)" : "") : "Within about 100 m")
            + (a.keys != null ? "  ·  " + a.keys + (a.keys === 1 ? " key" : " keys") : "");
    }

    // A message from the daemon ({ event, id, by, mine, distance, keys }), or a test one (id -1).
    function push(e) {
        if (!settings.notifyCubes) return;
        const now = Date.now();
        // A cube in range's banner: a new distance, or it's gone.
        if (e.event === "distance") {
            shown = shown.map(a => a.cube === e.id ? Object.assign({}, a, { distance: e.distance, at: now }) : a);
            return;
        }
        if (e.event === "left" || e.event === "opened") shown = shown.filter(a => a.cube !== e.id);
        if (e.event === "left") return;
        // No key, no use: unless the meter doesn't know your keys yet.
        if (e.event === "near" && settings.cubesNeedKey && e.keys === 0) return;
        let title, note;
        if (e.event === "near") {
            title = "Hidden cube nearby";
            // PipeWire's player, or PulseAudio's; neither is a hard dependency.
            if (settings.cubeSound) Quickshell.execDetached(["sh", "-c", 'pw-play "$0" 2>/dev/null || paplay "$0"', Quickshell.shellDir + "/sounds/cube.wav"]);
            shown = [{ key: ++count, cube: e.id, title: title, distance: e.distance, at: now, keys: e.keys, until: now + (e.id < 0 ? 10000 : 120000) }]
                .concat(shown.filter(a => a.until > now)).slice(0, 3);
            return;
        } else if (e.mine) {
            return; // You know: you're the one opening it.
        } else if (e.event === "opening") {
            // No name: it may be you, if the game hasn't said who you are yet.
            title = e.by ? e.by + " is opening a hidden cube" : "A hidden cube is being opened";
            note = "Nearby";
        } else {
            title = "Hidden cube opened";
            note = e.by ? "By " + e.by : "";
        }
        shown = [{ key: ++count, title: title, note: note, until: now + 7000 }]
            .concat(shown.filter(a => a.until > now)).slice(0, 3);
    }

    Connections {
        target: alerts.client
        function onCubeEvent(e) { alerts.push(e); }
    }
    Timer {
        interval: 500
        repeat: true
        running: alerts.active
        onTriggered: {
            alerts.now = Date.now();
            alerts.shown = alerts.shown.filter(a => a.until > alerts.now);
        }
    }

    Column {
        width: alerts.width_
        spacing: Math.round(6 * Theme.scale)

        // Something to place in Customize while there's no alert.
        Panel {
            visible: !alerts.active
            width: alerts.width_
            Text {
                text: "Hidden cube alerts show here"
                color: Theme.dim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
            }
        }

        Repeater {
            model: alerts.shown
            Panel {
                required property var modelData
                width: alerts.width_
                border.color: Qt.alpha(AppTheme.cube, 0.6)
                Row {
                    spacing: Theme.pad
                    // The cube: a diamond in the map's cube colour.
                    Item {
                        width: Math.round(28 * Theme.scale)
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.62
                            height: width
                            rotation: 45
                            color: AppTheme.cube
                        }
                    }
                    Column {
                        width: alerts.width_ - Theme.pad * 4 - Math.round(28 * Theme.scale) - close.width
                        Text {
                            width: parent.width
                            text: modelData.title
                            elide: Text.ElideRight
                            color: Theme.text
                            font.pixelSize: Theme.fontLarge
                            font.family: Theme.fontFamily
                            font.bold: true
                        }
                        Text {
                            text: modelData.cube != null ? alerts.nearNote(modelData) : modelData.note
                            visible: text !== ""
                            color: Theme.dim
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.fontFamily
                        }
                    }
                    CloseX {
                        id: close
                        onClicked: alerts.shown = alerts.shown.filter(a => a.key !== modelData.key)
                    }
                }
            }
        }
    }
}
