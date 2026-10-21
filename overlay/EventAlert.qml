import QtQuick
import Quickshell

// Hourly event reminders below the cube alerts: the Shugo Festival at :00
// and the Dimensional Invasion at :30, server time. Each shows a few minutes
// before (Notifications page) with a countdown, and stays a minute after it
// starts. Turned on or off on the app's Notifications page.
OverlayWidget {
    id: alerts

    title: "Event reminders"
    // Takes clicks while a notification is up, for its ✕.
    interactive: active
    readonly property int width_: Math.round(380 * Theme.scale)
    defaultPos: Qt.point(Math.round((screen ? screen.width : 2560) / 2 - width_ / 2), Math.round(400 * hud))

    // The server clock is UTC+9, a whole number of hours from UTC: its :00 and :30 are UTC's.
    readonly property var events: [
        { id: "shugo", setting: "notifyShugo", minute: 0, name: "Shugo Festival", note: "Minigames: entry is only open for a few minutes", color: "#F2C15A" },
        { id: "invasion", setting: "notifyInvasion", minute: 30, name: "Dimensional Invasion", note: "Beritra Air Raid, Accursed Sword or Incursion of the Spirits", color: "#B48CF2" },
    ]
    property real now: Date.now()
    // A sample from the Notifications page: { id, start }.
    property var sample: null
    // Keys of the reminders already chimed for.
    property var chimed: []
    // The game is open: reminders only show then (a test from the app always does).
    property bool gameRunning: true
    // Keys of the reminders closed with their ✕.
    property var dismissed: []
    readonly property var shown: upcoming(now).filter(a => !dismissed.includes(a.key))
    readonly property bool active: shown.length > 0

    // The reminders due at `now`, while the game is open: each event that's on and
    // starts within the lead time, or started less than a minute ago. { key, name, note, color, start }, soonest first.
    function upcoming(now) {
        const hour = 3600000;
        const list = [];
        for (const ev of events) {
            if (!settings[ev.setting]) continue;
            if (!gameRunning && !(sample && sample.id === ev.id)) continue;
            let start = Math.floor((now - ev.minute * 60000) / hour) * hour + ev.minute * 60000;
            if (now - start >= 60000) start += hour;
            if (gameRunning && start - now <= settings.eventLead * 60000) list.push(Object.assign({ key: ev.id + start, start: start }, ev));
            if (sample && sample.id === ev.id && now < sample.start + 3000) list.push(Object.assign({ key: "sample", start: sample.start }, ev));
        }
        return list.sort((a, b) => a.start - b.start);
    }
    function countdown(a) {
        const s = Math.ceil((a.start - now) / 1000);
        return s <= 0 ? "Starting now" : "Starts in " + Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    function test(id) {
        sample = { id: id, start: Date.now() + 10000 };
        dismissed = dismissed.filter(k => k !== "sample");
        now = Date.now();
    }

    Timer {
        interval: 1000
        repeat: true
        running: alerts.settings.notifyShugo || alerts.settings.notifyInvasion
        onTriggered: alerts.now = Date.now()
    }
    onShownChanged: {
        const keys = shown.map(a => a.key);
        if (settings.eventSound && keys.some(k => !chimed.includes(k)))
            Quickshell.execDetached(["sh", "-c", 'pw-play "$0" 2>/dev/null || paplay "$0"', Quickshell.shellDir + "/sounds/cube.wav"]);
        chimed = keys;
    }

    Column {
        width: alerts.width_
        spacing: Math.round(6 * Theme.scale)

        // Something to place in Customize while there's no reminder.
        Panel {
            visible: !alerts.active
            width: alerts.width_
            Text {
                text: "Event reminders show here"
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
                border.color: Qt.alpha(modelData.color, 0.6)
                Row {
                    spacing: Theme.pad
                    Item {
                        width: Math.round(28 * Theme.scale)
                        height: width
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.6
                            height: width
                            radius: width / 2
                            color: modelData.color
                        }
                    }
                    Column {
                        width: alerts.width_ - Theme.pad * 4 - Math.round(28 * Theme.scale) - close.width
                        Text {
                            width: parent.width
                            text: modelData.name + "  ·  " + alerts.countdown(modelData)
                            elide: Text.ElideRight
                            color: Theme.text
                            font.pixelSize: Theme.fontLarge
                            font.family: Theme.fontFamily
                            font.bold: true
                        }
                        Text {
                            width: parent.width
                            text: modelData.note
                            elide: Text.ElideRight
                            color: Theme.dim
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.fontFamily
                        }
                    }
                    CloseX {
                        id: close
                        onClicked: alerts.dismissed = alerts.dismissed.concat([modelData.key])
                    }
                }
            }
        }
    }
}
