import QtQuick

// A small toggle/button used by the edit panel.
Rectangle {
    id: chip

    property string label
    property bool checked: false
    signal clicked()

    implicitWidth: text.implicitWidth + Theme.pad * 2
    implicitHeight: text.implicitHeight + Theme.pad
    radius: height / 2
    color: checked ? Theme.accent : (area.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))
    border.color: checked ? "transparent" : Theme.panelEdge

    Text {
        id: text
        anchors.centerIn: parent
        text: chip.label
        color: chip.checked ? "#1b1b1b" : Theme.text
        font.pixelSize: Theme.fontSmall
        font.family: Theme.fontFamily
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
