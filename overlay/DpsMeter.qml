import QtQuick

// Ranked players on the current target: DPS, damage, share and crit rate.
OverlayWidget {
    id: meter

    required property var client
    title: "DPS meter"
    defaultPos: Qt.point(24, Math.round((screen ? screen.height : 1200) * 0.30))

    readonly property int width_: Math.round(390 * Theme.scale)
    readonly property var rows: client.players.slice(0, settings.maxRows)
    readonly property real topDamage: rows.length ? rows[0].damage : 1
    readonly property var localRow: client.players.find(p => p.isLocal)

    // A click on a row (edit mode) shows that player's skills.
    onTapped: (x, y) => {
        const i = Math.floor((y - list.y - Theme.pad) / (Theme.rowHeight + list.spacing));
        if (i >= 0 && i < rows.length) client.focus(rows[i].isLocal ? null : rows[i].id);
    }

    Panel {
        width: meter.width_

        // Header: mode, target, timer
        Item {
            width: meter.width_ - Theme.pad * 2
            height: Math.round(18 * Theme.scale)
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - timer.width - Theme.pad
                elide: Text.ElideRight
                text: {
                    const t = meter.client.target;
                    if (!meter.client.connected) return "Meter daemon not running";
                    return t && t.name ? t.name : modeName(meter.client.state ? meter.client.state.targetMode : "");
                }
                color: Theme.text
                font.pixelSize: Theme.fontNormal
                font.family: Theme.fontFamily
                font.bold: true

                function modeName(m) {
                    return ({ bossTargets: "Boss", lastHitByMe: "My target", mostDamage: "Most damaged",
                              mostRecent: "Most recent", allTargets: "All targets", trainTargets: "Training dummy" })[m] || "Meter";
                }
            }
            Text {
                id: timer
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: meter.client.state ? Theme.duration(meter.client.state.battleTimeMs) : "-:--"
                color: Theme.dim
                font.pixelSize: Theme.fontNormal
                font.family: Theme.fontFamily
                font.features: { "tnum": 1 }
            }
        }

        MeterHeader {
            metric: meter.settings.meterMetric
            visible: meter.rows.length > 0
            width: meter.width_ - Theme.pad * 2
        }

        Column {
            id: list
            spacing: Math.round(2 * Theme.scale)

            Repeater {
                model: meter.rows
                PlayerBar {
                    metric: meter.settings.meterMetric
                    required property var modelData
                    required property int index
                    width: meter.width_ - Theme.pad * 2
                    player: modelData
                    rank: index + 1
                    fraction: modelData.damage / meter.topDamage
                    focused: meter.client.state && meter.client.state.skillsOf === modelData.id && !modelData.isLocal
                }
            }

            // You, when you are below the cut.
            PlayerBar {
                metric: meter.settings.meterMetric
                visible: meter.localRow !== undefined && !meter.rows.some(r => r.isLocal)
                width: meter.width_ - Theme.pad * 2
                player: meter.localRow || null
                rank: meter.client.players.indexOf(meter.localRow) + 1
                fraction: meter.localRow ? meter.localRow.damage / meter.topDamage : 0
            }

            Text {
                visible: meter.rows.length === 0
                text: {
                    const c = meter.client.capture;
                    if (!meter.client.connected) return "Start aion2-meterd (systemctl --user start aion2-meterd)";
                    if (c && c.error) return "Capture error — see the status widget";
                    if (c && !c.gameRunning) return "Waiting for AION 2…";
                    if (c && !c.locked) return "Waiting for game traffic…";
                    return "No damage yet";
                }
                color: Theme.faint
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
            }
        }

        // Footer: party total
        Item {
            visible: meter.rows.length > 0
            width: meter.width_ - Theme.pad * 2
            height: Math.round(16 * Theme.scale)
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Total"
                color: Theme.faint
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const m = meter.settings.meterMetric;
                    const dmg = Theme.compact(meter.client.totalDamage) + " total";
                    const dps = Theme.compact(meter.client.totalDps) + "/s";
                    return m === "damage" ? dmg : m === "dps" ? dps : dmg + "   " + dps;
                }
                color: Theme.dim
                font.pixelSize: Theme.fontSmall
                font.family: Theme.fontFamily
                font.features: { "tnum": 1 }
            }
        }
    }
}
