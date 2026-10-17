import QtQuick

// One player's skills: damage share, DPS, hits, crit and back-attack rates.
// Drawn by the live skills widget and by past fights in the history.
Column {
    id: table

    property var rows: []
    property string title: "Skills"
    property color titleColor: Theme.text
    property color barColor: Theme.accent
    readonly property real topDamage: rows.length ? rows[0].damage : 1

    spacing: Math.round(3 * Theme.scale)

    Item {
        width: table.width
        height: Math.round(18 * Theme.scale)
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: table.title
            color: table.titleColor
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
        model: table.rows
        Item {
            id: row
            required property var modelData
            width: table.width
            height: Math.round(Theme.rowHeight * 0.9)

            Rectangle {
                anchors.fill: parent
                radius: 3
                color: Theme.rowBg
            }
            Rectangle {
                width: Math.max(2, parent.width * row.modelData.damage / table.topDamage)
                height: parent.height
                radius: 3
                color: Qt.alpha(table.barColor, row.modelData.isDot ? 0.22 : 0.34)
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            }
            // The slot stays when there's no icon (basic attacks) so names line up.
            Image {
                id: icon
                anchors.left: parent.left
                anchors.leftMargin: Math.round(3 * Theme.scale)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - Math.round(4 * Theme.scale)
                height: width
                source: row.modelData.icon || ""
                sourceSize: Qt.size(width * 2, height * 2)
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
            Text {
                anchors.left: icon.right
                anchors.leftMargin: Math.round(5 * Theme.scale)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - icon.width - stats.width - Math.round(16 * Theme.scale)
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
        visible: table.rows.length === 0
        text: "No skills yet"
        color: Theme.faint
        font.pixelSize: Theme.fontSmall
        font.family: Theme.fontFamily
    }
}
