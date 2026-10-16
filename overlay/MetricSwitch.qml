import QtQuick

// Damage | DPS | Both: which numbers a player list shows.
Row {
    id: sw

    property string value: "both"
    signal picked(string metric)

    spacing: Math.round(2 * Theme.scale)

    Repeater {
        model: [["damage", "Damage"], ["dps", "DPS"], ["both", "Both"]]
        Chip {
            required property var modelData
            label: modelData[1]
            checked: sw.value === modelData[0]
            onClicked: sw.picked(modelData[0])
        }
    }
}
