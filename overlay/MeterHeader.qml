import QtQuick

// Column labels above PlayerBar rows, aligned with its columns.
Item {
    id: header
    property string metric: "both"
    height: Math.round(14 * Theme.scale)

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Math.round(6 * Theme.scale)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.colSpacing
        Repeater {
            model: [["CP", Theme.colCp], ["Damage", Theme.colDamage], ["DPS", Theme.colDps], ["%", Theme.colShare], ["Crit", Theme.colCrit]]
                .filter(c => !(header.metric === "dps" && c[0] === "Damage") && !(header.metric === "damage" && c[0] === "DPS"))
            Text {
                required property var modelData
                text: modelData[0]
                width: modelData[1]
                horizontalAlignment: Text.AlignRight
                color: Theme.faint
                font.pixelSize: Math.round(10 * Theme.scale)
                font.family: Theme.fontFamily
            }
        }
    }
}
