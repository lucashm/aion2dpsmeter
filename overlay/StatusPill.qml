import QtQuick

// Ping (four bars, like questlog's) and the capture's state. Problems
// (no daemon, no capture permission) show here in words.
OverlayWidget {
    id: status

    required property var client
    title: "Ping"
    defaultPos: Qt.point(Math.round((screen ? screen.width : 2560) - 200 * Theme.scale), Math.round(12 * Theme.scale))

    readonly property var capture: client.capture
    readonly property var ping: client.state ? client.state.pingMs : null
    readonly property string problem: {
        if (!client.connected) return "meter daemon not running";
        if (capture && capture.error) {
            return capture.error.indexOf("cap_net_raw") >= 0 || capture.error.indexOf("CAP_NET_RAW") >= 0
                ? "no capture permission — run scripts/install.sh"
                : capture.error;
        }
        return "";
    }
    readonly property string stateText: {
        if (problem) return problem;
        if (!capture || !capture.gameRunning) return "game not running";
        if (!capture.locked) return "finding game traffic…";
        return ping !== null ? ping + " ms" : "connected";
    }
    readonly property color pingColor: ping === null ? Theme.faint : ping < 80 ? Theme.good : ping < 160 ? Theme.warn : Theme.bad
    readonly property int bars: ping === null ? 0 : ping < 60 ? 4 : ping < 110 ? 3 : ping < 180 ? 2 : 1

    Panel {
        padding: Math.round(5 * Theme.scale)

        Row {
            spacing: Math.round(6 * Theme.scale)

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(2 * Theme.scale)
                visible: !status.problem
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        anchors.bottom: parent.bottom
                        width: Math.round(3 * Theme.scale)
                        height: Math.round((4 + index * 3) * Theme.scale)
                        radius: 1
                        color: index < status.bars ? status.pingColor : Qt.rgba(1, 1, 1, 0.15)
                    }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: status.problem ? "⚠" : ""
                visible: !!status.problem
                color: Theme.bad
                font.pixelSize: Theme.fontSmall
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: status.stateText
                color: status.problem ? Theme.bad : (status.capture && status.capture.locked && status.ping !== null ? status.pingColor : Theme.dim)
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                font.features: { "tnum": 1 }
            }
        }
    }
}
