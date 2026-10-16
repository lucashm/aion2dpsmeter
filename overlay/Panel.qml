import QtQuick

// The dark rounded card every widget is drawn on.
Rectangle {
    default property alias content: inner.data
    property int padding: Theme.pad

    implicitWidth: inner.implicitWidth + padding * 2
    implicitHeight: inner.implicitHeight + padding * 2
    radius: Theme.radius
    color: Theme.panel
    border.color: Theme.panelEdge
    border.width: 1

    Column {
        id: inner
        x: parent.padding
        y: parent.padding
        spacing: Math.round(3 * Theme.scale)
    }
}
