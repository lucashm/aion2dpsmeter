import QtQuick

// One meter row: a class-coloured bar behind rank, name, DPS, share, crit.
Item {
    id: row

    property var player: null
    property int rank: 0
    property real fraction: 0
    property bool focused: false
    // "both", "damage" or "dps"
    property string metric: "both"

    readonly property color jobColor: player ? Theme.jobColor(player.jobKey) : Theme.faint

    height: Theme.rowHeight

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: Theme.rowBg
        border.color: row.player && row.player.isLocal ? Qt.rgba(1, 1, 1, 0.35) : (row.focused ? Theme.accent : "transparent")
        border.width: 1
    }
    Rectangle {
        width: Math.max(2, parent.width * Math.min(1, row.fraction))
        height: parent.height
        radius: 4
        color: Qt.alpha(row.jobColor, 0.42)
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: Math.round(6 * Theme.scale)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(6 * Theme.scale)

        Text {
            text: row.rank
            color: Theme.dim
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
            font.features: { "tnum": 1 }
            width: Math.round(12 * Theme.scale)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(4 * Theme.scale)
            height: Math.round(12 * Theme.scale)
            radius: 2
            color: row.jobColor
        }
        Text {
            text: row.player ? row.player.name : ""
            color: Theme.text
            font.pixelSize: Theme.fontNormal
            font.family: Theme.fontFamily
            font.bold: row.player && row.player.isLocal
            elide: Text.ElideRight
            width: row.width - stats.width - Math.round(48 * Theme.scale)
        }
    }

    Row {
        id: stats
        anchors.right: parent.right
        anchors.rightMargin: Math.round(6 * Theme.scale)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.colSpacing

        Text {
            visible: row.metric !== "dps"
            text: row.player ? Theme.compact(row.player.damage) : ""
            color: Theme.text
            font.pixelSize: Theme.fontNormal
            font.family: Theme.fontFamily
            font.features: { "tnum": 1 }
            horizontalAlignment: Text.AlignRight
            width: Theme.colDamage
        }
        Text {
            visible: row.metric !== "damage"
            text: row.player ? Theme.compact(row.player.dps) : ""
            // The main number when it is the only one.
            color: row.metric === "dps" ? Theme.text : Theme.dim
            font.pixelSize: row.metric === "dps" ? Theme.fontNormal : Theme.fontSmall
            font.family: Theme.fontFamily
            font.features: { "tnum": 1 }
            horizontalAlignment: Text.AlignRight
            width: Theme.colDps
        }
        Text {
            text: row.player ? Theme.percent(row.player.share / 100, 0) : ""
            color: Theme.dim
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
            font.features: { "tnum": 1 }
            horizontalAlignment: Text.AlignRight
            width: Theme.colShare
        }
        Text {
            text: row.player && row.player.critRate > 0 ? Theme.percent(row.player.critRate, 0) : "–"
            color: Theme.faint
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
            font.features: { "tnum": 1 }
            horizontalAlignment: Text.AlignRight
            width: Theme.colCrit
        }
    }
}
