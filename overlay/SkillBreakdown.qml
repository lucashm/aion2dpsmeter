import QtQuick

// The focused player's skills (yours unless you picked someone in the meter):
// damage share, DPS, hits, crit and back-attack rates.
OverlayWidget {
    id: skills

    required property var client
    title: "Skills"
    defaultPos: Qt.point(24, Math.round((screen ? screen.height : 1200) * 0.30) + Math.round(290 * Theme.scale))

    readonly property int width_: Math.round(360 * Theme.scale)
    readonly property var rows: client.skills.slice(0, settings.skillRows)
    readonly property real topDamage: rows.length ? rows[0].damage : 1
    readonly property var owner: {
        const s = client.state;
        if (!s || s.skillsOf === null) return null;
        return client.players.find(p => p.id === s.skillsOf) || null;
    }

    Panel {
        width: skills.width_

        Item {
            width: skills.width_ - Theme.pad * 2
            height: Math.round(18 * Theme.scale)
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: skills.owner ? skills.owner.name + (skills.owner.job ? "  ·  " + skills.owner.job : "") : "Skills"
                color: skills.owner ? Theme.jobColor(skills.owner.jobKey) : Theme.text
                font.pixelSize: Theme.fontNormal
                font.family: Theme.fontFamily
                font.bold: true
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: Math.round(6 * Theme.scale)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(8 * Theme.scale)
                Repeater {
                    model: [["DPS", 48], ["Hits", 30], ["Crit", 32], ["Back", 32]]
                    Text {
                        required property var modelData
                        text: modelData[0]
                        width: Math.round(modelData[1] * Theme.scale)
                        horizontalAlignment: Text.AlignRight
                        color: Theme.faint
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                    }
                }
            }
        }

        Repeater {
            model: skills.rows
            Item {
                id: row
                required property var modelData
                width: skills.width_ - Theme.pad * 2
                height: Math.round(Theme.rowHeight * 0.9)

                Rectangle {
                    anchors.fill: parent
                    radius: 3
                    color: Theme.rowBg
                }
                Rectangle {
                    width: Math.max(2, parent.width * row.modelData.damage / skills.topDamage)
                    height: parent.height
                    radius: 3
                    color: Qt.alpha(skills.owner ? Theme.jobColor(skills.owner.jobKey) : Theme.accent, row.modelData.isDot ? 0.22 : 0.34)
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Math.round(6 * Theme.scale)
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - stats.width - Math.round(14 * Theme.scale)
                    elide: Text.ElideRight
                    text: (row.modelData.name || ("#" + row.modelData.code)) + (row.modelData.isDot ? " (DoT)" : "")
                        + "  " + Theme.percent(row.modelData.share, 0)
                    color: Theme.text
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                }
                Row {
                    id: stats
                    anchors.right: parent.right
                    anchors.rightMargin: Math.round(6 * Theme.scale)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.round(8 * Theme.scale)
                    Repeater {
                        model: [
                            [Theme.compact(row.modelData.dps), 48, Theme.text],
                            [row.modelData.hits, 30, Theme.dim],
                            [row.modelData.isDot ? "–" : Theme.percent(row.modelData.critRate, 0), 32, Theme.dim],
                            [row.modelData.isDot ? "–" : Theme.percent(row.modelData.backRate, 0), 32, Theme.dim]
                        ]
                        Text {
                            required property var modelData
                            text: modelData[0]
                            width: Math.round(modelData[1] * Theme.scale)
                            horizontalAlignment: Text.AlignRight
                            color: modelData[2]
                            font.pixelSize: Theme.fontSmall
                            font.family: Theme.fontFamily
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }
        }

        Text {
            visible: skills.rows.length === 0
            text: "No skills yet"
            color: Theme.faint
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
        }
    }
}
