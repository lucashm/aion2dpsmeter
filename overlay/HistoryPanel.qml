import QtQuick

// Saved boss fights. Opened with the history key; while open it takes the
// pointer (only over itself) so fights can be picked.
OverlayWidget {
    id: hist

    required property var client
    property bool open: false
    property string selected: ""
    readonly property string metric: settings.historyMetric
    // The selected fight's summary, once the daemon has sent it.
    readonly property var fight: selected && client.fight && client.fight.summary.id === selected ? client.fight.summary : null
    // Your name, to highlight your row in old fights.
    readonly property string localName: {
        const me = client.players.find(p => p.isLocal);
        return me ? me.name : "";
    }

    title: "History"
    interactive: open
    // Only when opened: not part of edit mode's layout.
    visible: open
    readonly property int width_: Math.round(440 * Theme.scale)
    defaultPos: Qt.point(Math.round(((screen ? screen.width : 2560) - width_) / 2), Math.round((screen ? screen.height : 1440) * 0.22))

    onOpenChanged: {
        if (open) {
            selected = "";
            client.requestHistory();
        }
    }
    Connections {
        target: hist.client
        function onFightSaved() {
            if (hist.open) hist.client.requestHistory();
        }
    }

    Panel {
        width: hist.width_

        Item {
            width: hist.width_ - Theme.pad * 2
            height: Math.round(20 * Theme.scale)
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: hist.selected ? "‹ Fights" : "Fight history"
                color: Theme.text
                font.pixelSize: Theme.fontNormal
                font.family: Theme.fontFamily
                font.bold: true
                MouseArea {
                    anchors.fill: parent
                    enabled: hist.selected !== ""
                    cursorShape: Qt.PointingHandCursor
                    onClicked: hist.selected = ""
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(4 * Theme.scale)
                MetricSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    value: hist.metric
                    onPicked: m => hist.settings.setHistoryMetric(m)
                }
                Item { width: Theme.pad; height: 1 }
                Chip {
                    label: "Close"
                    onClicked: hist.open = false
                }
            }
        }

        // ── list ──
        Repeater {
            model: hist.selected ? [] : hist.client.history
            Rectangle {
                id: item
                required property var modelData
                width: hist.width_ - Theme.pad * 2
                height: Math.round(34 * Theme.scale)
                radius: 4
                color: area.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Theme.rowBg

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.pad
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: (item.modelData.killed ? "✓ " : "") + (item.modelData.bossName || "Unknown")
                        color: item.modelData.killed ? Theme.good : Theme.text
                        font.pixelSize: Theme.fontNormal
                        font.family: Theme.fontFamily
                    }
                    Text {
                        text: new Date(item.modelData.startTimeMs).toLocaleString(Qt.locale(), "ddd d MMM, HH:mm")
                            + "  ·  " + Theme.duration(item.modelData.durationMs)
                            + "  ·  " + item.modelData.players.length + " players"
                        color: Theme.faint
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.pad
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const dmg = Theme.compact(item.modelData.totalDamage);
                        const dps = Theme.compact(item.modelData.totalDamage / Math.max(1, item.modelData.durationMs / 1000)) + "/s";
                        return hist.metric === "damage" ? dmg : hist.metric === "dps" ? dps : dmg + "   " + dps;
                    }
                    color: Theme.dim
                    font.pixelSize: Theme.fontNormal
                    font.family: Theme.fontFamily
                    font.features: { "tnum": 1 }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Through a function on the panel: switching to the fight
                    // destroys this row mid-handler.
                    onClicked: hist.openFight(item.modelData.id)
                }
            }
        }
        Text {
            visible: !hist.selected && hist.client.history.length === 0
            text: "No saved fights yet. Boss fights are saved when they end."
            color: Theme.faint
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
        }

        // ── one fight ──
        Column {
            visible: hist.fight !== null
            spacing: Math.round(3 * Theme.scale)
            width: hist.width_ - Theme.pad * 2

            Text {
                text: hist.fight ? (hist.fight.killed ? "✓ " : "") + (hist.fight.bossName || "Unknown") : ""
                color: hist.fight && hist.fight.killed ? Theme.good : Theme.text
                font.pixelSize: Theme.fontLarge
                font.family: Theme.fontFamily
                font.bold: true
            }
            Text {
                text: hist.fight
                    ? Theme.compact(hist.fight.totalDamage) + " damage  ·  "
                      + Theme.compact(hist.fight.totalDamage / Math.max(1, hist.fight.durationMs / 1000)) + "/s party DPS  ·  "
                      + Theme.duration(hist.fight.durationMs)
                    : ""
                color: Theme.dim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                font.features: { "tnum": 1 }
            }
            MeterHeader { width: parent.width; metric: hist.metric }
            Repeater {
                model: hist.fight ? hist.fight.players : []
                PlayerBar {
                    required property var modelData
                    required property int index
                    metric: hist.metric
                    width: hist.width_ - Theme.pad * 2
                    rank: index + 1
                    fraction: modelData.damage / Math.max(1, hist.fight.players[0].damage)
                    player: ({
                        name: modelData.name,
                        jobKey: modelData.jobKey,
                        damage: modelData.damage,
                        dps: modelData.dps,
                        share: hist.fight.totalDamage > 0 ? modelData.damage / hist.fight.totalDamage * 100 : 0,
                        critRate: hist.critRate(modelData.id),
                        isLocal: modelData.name === hist.localName
                    })
                }
            }
        }
        Text {
            visible: hist.selected !== "" && hist.fight === null
            text: "Loading…"
            color: Theme.faint
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
        }
    }

    function openFight(id) {
        client.requestFight(id);
        selected = id;
    }

    function critRate(actorId) {
        const f = client.fight;
        if (!f) return 0;
        let crit = 0, hits = 0;
        for (const s of f.skills) {
            if (s.actorId !== actorId || s.isDot) continue;
            crit += s.crit;
            hits += s.hits;
        }
        return hits > 0 ? crit / hits : 0;
    }
}
