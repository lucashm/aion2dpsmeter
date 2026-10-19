import QtQuick

// The ✕ that closes a notification, in its top right corner.
Text {
    id: closeX
    signal clicked()
    width: Math.round(16 * Theme.scale)
    horizontalAlignment: Text.AlignRight
    anchors.top: parent.top
    text: "✕"
    color: area.containsMouse ? Theme.text : Theme.dim
    font.pixelSize: Theme.fontSmall
    font.family: Theme.fontFamily
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: closeX.clicked()
    }
}
